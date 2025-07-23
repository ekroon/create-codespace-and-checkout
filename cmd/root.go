package cmd

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"github.com/cli/go-gh/v2"
	"github.com/spf13/cobra"
)

// Colors for output
const (
	ColorRed    = "\033[0;31m"
	ColorGreen  = "\033[0;32m"
	ColorYellow = "\033[1;33m"
	ColorNC     = "\033[0m" // No Color
)

// Command line flags
var (
	repo               string
	codespaceSize      string
	devcontainerPath   string
	defaultPermissions bool
	branchName         string
	verbose            bool
)

var rootCmd = &cobra.Command{
	Use:   "create-codespace-and-checkout [branch-name]",
	Short: "Create a new codespace and checkout a git branch",
	Long: `Create a new codespace and checkout a git branch.

Options:
  -R <repo>               Repository (default: github/github, env: REPO)
  -m <machine-type>       Codespace machine type (default: xLargePremiumLinux, env: CODESPACE_SIZE)
  --devcontainer-path <path>  Path to devcontainer (default: .devcontainer/devcontainer.json, env: DEVCONTAINER_PATH)
  --default-permissions   Use default permissions without authorization prompt
  --verbose               Show verbose output including command errors for debugging`,
	Args: cobra.MaximumNArgs(1),
	Run:  runCreateCodespace,
}

func init() {
	// Set defaults from environment variables or use built-in defaults
	rootCmd.Flags().StringVarP(&repo, "repo", "R", getEnvOrDefault("REPO", "github/github"), "Repository")
	rootCmd.Flags().StringVarP(&codespaceSize, "machine-type", "m", getEnvOrDefault("CODESPACE_SIZE", "xLargePremiumLinux"), "Codespace machine type")
	rootCmd.Flags().StringVar(&devcontainerPath, "devcontainer-path", getEnvOrDefault("DEVCONTAINER_PATH", ".devcontainer/devcontainer.json"), "Path to devcontainer")
	rootCmd.Flags().BoolVar(&defaultPermissions, "default-permissions", false, "Use default permissions without authorization prompt")
	rootCmd.Flags().BoolVar(&verbose, "verbose", false, "Show verbose output including command errors for debugging")
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		printError(err.Error())
		os.Exit(1)
	}
}

func getEnvOrDefault(envVar, defaultValue string) string {
	if value := os.Getenv(envVar); value != "" {
		return value
	}
	return defaultValue
}

func printStatus(message string) {
	fmt.Printf("%s[INFO]%s %s\n", ColorGreen, ColorNC, message)
}

func printWarning(message string) {
	fmt.Printf("%s[WARNING]%s %s\n", ColorYellow, ColorNC, message)
}

func printError(message string) {
	fmt.Printf("%s[ERROR]%s %s\n", ColorRed, ColorNC, message)
}

func printVerbose(message string) {
	if verbose {
		fmt.Printf("%s[DEBUG]%s %s\n", ColorYellow, ColorNC, message)
	}
}

func runCreateCodespace(cmd *cobra.Command, args []string) {
	// Get branch name from args or prompt
	if len(args) > 0 {
		branchName = args[0]
	}

	if branchName == "" {
		fmt.Print("Enter the branch name to checkout: ")
		scanner := bufio.NewScanner(os.Stdin)
		if scanner.Scan() {
			branchName = strings.TrimSpace(scanner.Text())
		}
		if branchName == "" {
			printError("Branch name is required")
			os.Exit(1)
		}
	}

	// Extract repository name from repo (e.g., "github/github" -> "github")
	repoName := strings.Split(repo, "/")[1]

	printStatus("Starting codespace creation process...")

	// Step 1: Create the codespace
	codespaceName, err := createCodespace()
	if err != nil {
		handleCodespaceCreationError(err)
		os.Exit(1)
	}

	printStatus(fmt.Sprintf("Codespace created successfully: %s", codespaceName))

	// Step 2: Wait for codespace to be ready
	if err := waitForCodespaceReady(codespaceName, repoName); err != nil {
		printError(err.Error())
		os.Exit(1)
	}

	// Step 3: Fetch latest remote information
	if err := fetchRemoteInfo(codespaceName, repoName); err != nil {
		printError("Failed to fetch from remote. Git authentication may not be ready yet.")
		printWarning(fmt.Sprintf("Try connecting to the codespace manually: gh cs ssh -c %s", codespaceName))
		os.Exit(1)
	}

	// Step 4: Upload terminfo
	uploadTerminfo(codespaceName)

	// Step 5: Checkout branch
	if err := checkoutBranch(codespaceName, repoName, branchName); err != nil {
		printError(fmt.Sprintf("Failed to checkout branch '%s'", branchName))
		printWarning(fmt.Sprintf("Codespace '%s' was created but branch checkout failed", codespaceName))
		os.Exit(1)
	}

	// Step 6: Wait for configuration to complete
	waitForConfiguration(codespaceName)

	printStatus(fmt.Sprintf("Setup complete! Your codespace is ready with branch '%s' checked out.", branchName))
	printStatus(fmt.Sprintf("Connect with: gh cs ssh -c %s", codespaceName))
}

func createCodespace() (string, error) {
	printStatus(fmt.Sprintf("Creating new codespace with %s machine type...", codespaceSize))

	args := []string{"cs", "create", "-R", repo, "-m", codespaceSize, "--devcontainer-path", devcontainerPath}
	if defaultPermissions {
		args = append(args, "--default-permissions")
	}

	printVerbose(fmt.Sprintf("Running command: gh %s", strings.Join(args, " ")))

	stdout, stderr, err := gh.Exec(args...)

	if err != nil {
		printVerbose(fmt.Sprintf("Codespace creation failed: %v", err))
		printVerbose(fmt.Sprintf("Command stderr: %s", stderr.String()))
		printVerbose(fmt.Sprintf("Command stdout: %s", stdout.String()))
		return "", fmt.Errorf("failed to create codespace: %s", stderr.String())
	}

	output := stdout.String()
	printVerbose(fmt.Sprintf("Codespace creation output: %s", output))

	// Extract the codespace name (last line of output)
	lines := strings.Split(strings.TrimSpace(output), "\n")
	codespaceName := strings.TrimSpace(lines[len(lines)-1])

	printVerbose(fmt.Sprintf("Extracted codespace name: %s", codespaceName))

	return codespaceName, nil
}

func handleCodespaceCreationError(err error) {
	errorMsg := err.Error()

	// Check if the failure is due to permissions authorization required
	if strings.Contains(errorMsg, "You must authorize or deny additional permissions") {
		printError("Codespace creation requires additional permissions authorization")
		printError("Please authorize the permissions in your browser, then try again")

		// Extract authorization URL if present
		re := regexp.MustCompile(`https://github\.com/[^\s]*`)
		if match := re.FindString(errorMsg); match != "" {
			printStatus(fmt.Sprintf("Authorization URL: %s", match))
		}

		printWarning("Alternatively, you can rerun this script with --default-permissions option")
	} else {
		printError("Failed to create codespace")
		printError(errorMsg)
	}
}

func waitForCodespaceReady(codespaceName, repoName string) error {
	printStatus("Waiting for codespace to be fully ready...")
	maxAttempts := 30

	for attempt := 1; attempt <= maxAttempts; attempt++ {
		printStatus(fmt.Sprintf("Checking codespace readiness (attempt %d/%d)...", attempt, maxAttempts))

		// Check if we can successfully connect and the workspace is ready
		// Use bash -c instead of bash -l -c since login shell has issues during early startup
		testCmd := fmt.Sprintf("test -d /workspaces/%s && cd /workspaces/%s && pwd", repoName, repoName)
		fullCmd := fmt.Sprintf("bash -c '%s'", testCmd)

		printVerbose(fmt.Sprintf("Running command: gh cs ssh -c %s -- \"%s\"", codespaceName, fullCmd))

		stdout, stderr, err := gh.Exec("cs", "ssh", "-c", codespaceName, "--", fullCmd)
		if err == nil {
			printStatus("Codespace is ready!")
			printVerbose(fmt.Sprintf("Command succeeded with output: %s", strings.TrimSpace(stdout.String())))
			return nil
		}

		// If command failed, do some basic debugging
		printVerbose(fmt.Sprintf("Codespace readiness check failed: %v", err))
		printVerbose(fmt.Sprintf("Command stdout: %s", stdout.String()))
		printVerbose(fmt.Sprintf("Command stderr: %s", stderr.String()))

		if attempt == maxAttempts {
			return fmt.Errorf("codespace failed to become ready after %d attempts", maxAttempts)
		}

		time.Sleep(10 * time.Second)
	}

	return nil
}

func fetchRemoteInfo(codespaceName, repoName string) error {
	fmt.Printf("%s[INFO]%s Fetching latest remote information...", ColorGreen, ColorNC)

	// Use login shell like the original script - git auth is set up there
	gitCmd := fmt.Sprintf("cd /workspaces/%s && git fetch origin", repoName)
	fullCmd := fmt.Sprintf("bash -l -c '%s'", gitCmd)

	printVerbose(fmt.Sprintf("Running command: gh cs ssh -c %s -- \"%s\"", codespaceName, fullCmd))

	stdout, stderr, err := gh.Exec("cs", "ssh", "-c", codespaceName, "--", fullCmd)
	if err == nil {
		fmt.Println(" ✓")
		printVerbose(fmt.Sprintf("Git fetch succeeded with output: %s", strings.TrimSpace(stdout.String())))
		return nil
	}

	printVerbose(fmt.Sprintf("Git fetch failed: %v", err))
	printVerbose(fmt.Sprintf("Git fetch stdout: %s", stdout.String()))
	printVerbose(fmt.Sprintf("Git fetch stderr: %s", stderr.String()))

	fmt.Println(" ✗")
	return err
}

func uploadTerminfo(codespaceName string) {
	printStatus("Uploading xterm-ghostty terminfo to codespace...")

	// Get terminfo output - keep using exec.Command for non-gh commands
	infoCmd := exec.Command("infocmp", "-x", "xterm-ghostty")
	terminfo, err := infoCmd.Output()
	if err != nil {
		printWarning("Failed to get xterm-ghostty terminfo. Terminal features may be limited.")
		return
	}

	// Upload to codespace using gh.Exec - note: gh.Exec doesn't support stdin directly
	// We need to use a different approach, possibly writing to a temp file first
	// For now, let's keep this as exec.Command since gh.Exec doesn't have stdin support
	ghCmd := exec.Command("gh", "cs", "ssh", "-c", codespaceName, "--", "tic", "-x", "-")
	ghCmd.Stdin = strings.NewReader(string(terminfo))

	if err := ghCmd.Run(); err != nil {
		printWarning("Failed to upload xterm-ghostty terminfo. Terminal features may be limited.")
	} else {
		printStatus("Successfully uploaded xterm-ghostty terminfo.")
	}
}

func checkoutBranch(codespaceName, repoName, branchName string) error {
	printStatus(fmt.Sprintf("Checking if branch '%s' exists remotely...", branchName))

	// Check if branch exists remotely - use login shell like the original script
	lsRemoteCmd := fmt.Sprintf("cd /workspaces/%s && git ls-remote --heads origin %s", repoName, branchName)
	lsRemoteFullCmd := fmt.Sprintf("bash -l -c '%s'", lsRemoteCmd)

	printVerbose(fmt.Sprintf("Git ls-remote command: gh cs ssh -c %s -- \"%s\"", codespaceName, lsRemoteFullCmd))

	stdout, stderr, err := gh.Exec("cs", "ssh", "-c", codespaceName, "--", lsRemoteFullCmd)

	if err != nil {
		printVerbose(fmt.Sprintf("Git ls-remote failed: %v", err))
		printVerbose(fmt.Sprintf("Git ls-remote stdout: %s", stdout.String()))
		printVerbose(fmt.Sprintf("Git ls-remote stderr: %s", stderr.String()))
	} else {
		printVerbose(fmt.Sprintf("Git ls-remote output: %s", stdout.String()))
	}

	// Match original bash logic: check if output is non-empty (not just error status)
	remoteExists := err == nil && len(strings.TrimSpace(stdout.String())) > 0

	var checkoutCmd string
	if remoteExists {
		printStatus(fmt.Sprintf("Branch '%s' exists remotely, checking out...", branchName))
		checkoutCmd = fmt.Sprintf("cd /workspaces/%s && git checkout %s", repoName, branchName)
	} else {
		printWarning(fmt.Sprintf("Branch '%s' doesn't exist remotely. Creating new branch...", branchName))
		checkoutCmd = fmt.Sprintf("cd /workspaces/%s && git checkout -b %s", repoName, branchName)
	}

	checkoutFullCmd := fmt.Sprintf("bash -l -c '%s'", checkoutCmd)

	printVerbose(fmt.Sprintf("Running checkout command: gh cs ssh -c %s -- \"%s\"", codespaceName, checkoutFullCmd))

	checkoutStdout, checkoutStderr, err := gh.Exec("cs", "ssh", "-c", codespaceName, "--", checkoutFullCmd)
	if err != nil {
		printVerbose(fmt.Sprintf("Git checkout failed: %v", err))
		printVerbose(fmt.Sprintf("Git checkout stdout: %s", checkoutStdout.String()))
		printVerbose(fmt.Sprintf("Git checkout stderr: %s", checkoutStderr.String()))
		return err
	}

	printStatus(fmt.Sprintf("Successfully checked out branch '%s' in codespace '%s'", branchName, codespaceName))
	return nil
}

func waitForConfiguration(codespaceName string) {
	printStatus("Waiting for codespace configuration to complete...")
	maxAttempts := 60 // 10 minutes total (60 * 10 seconds)

	for attempt := 1; attempt <= maxAttempts; attempt++ {
		printStatus(fmt.Sprintf("Checking configuration status (attempt %d/%d)...", attempt, maxAttempts))

		// Get codespace logs and extract the last line
		// Using gh.Exec for the logs command, then process the output
		stdout, stderr, err := gh.Exec("cs", "logs", "--codespace", codespaceName)

		if err == nil {
			output := stdout.String()
			lines := strings.Split(strings.TrimSpace(output), "\n")
			if len(lines) > 0 {
				lastLine := strings.TrimSpace(lines[len(lines)-1])
				printVerbose(fmt.Sprintf("Last log line: %s", lastLine))

				if strings.Contains(lastLine, "Finished configuring codespace.") {
					printStatus("Codespace configuration complete! ✓")
					return
				}
			}
		} else {
			printVerbose(fmt.Sprintf("Failed to get codespace logs: %v", err))
			printVerbose(fmt.Sprintf("Command stderr: %s", stderr.String()))
		}

		if attempt == maxAttempts {
			printWarning(fmt.Sprintf("Codespace configuration did not complete after %d attempts", maxAttempts))
			printWarning("The codespace may still be configuring in the background")
			return
		}

		time.Sleep(10 * time.Second)
	}
}
