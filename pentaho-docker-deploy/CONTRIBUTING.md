# Contributing to Pentaho Docker Deployment

Thank you for considering contributing to this project! This guide will help you get started with contributing to the Pentaho Docker Deployment automation.

## Table of Contents
- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Coding Standards](#coding-standards)

## Code of Conduct

This project follows a simple code of conduct:
- Be respectful and inclusive
- Focus on constructive feedback
- Help maintain a welcoming environment for all contributors

## Getting Started

### Prerequisites for Contributors
- Experience with bash shell scripting
- Basic understanding of AWS EC2 and Docker
- Access to Pentaho software files for testing
- Familiarity with Git and GitHub workflows

### Types of Contributions
- 🐛 **Bug fixes** - Fix issues with existing functionality
- ✨ **Feature enhancements** - Add new capabilities or improve existing ones
- 📖 **Documentation** - Improve README, comments, or guides
- 🧪 **Testing** - Add or improve test coverage
- 🔧 **Infrastructure** - Improve build, deployment, or CI/CD processes

## Development Setup

### 1. Fork and Clone
```bash
# Fork the repository on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/pentaho-docker-deploy.git
cd pentaho-docker-deploy

# Add upstream remote
git remote add upstream https://github.com/ORIGINAL_OWNER/pentaho-docker-deploy.git
```

### 2. Create Development Environment
```bash
# Copy the test environment for development
cp pentaho-deployment-test.env pentaho-deployment-dev.env

# Edit with your development AWS settings
# Use a separate AWS account/region if possible to avoid conflicts
```

### 3. Add Required Files
Place Pentaho installation files in `pentaho-downloads/`:
- `pentaho-server-ee-10.2.0.0-222.zip`
- `paz-plugin-ee-10.2.0.0-222.zip`
- `dock-maker-10.2.0.0-222-public.zip`

### 4. Verify Setup
```bash
# Test your development environment
./01-create-pentaho-ec2.sh dev
./teardown-instance.sh dev
```

## Making Changes

### 1. Create Feature Branch
```bash
# Create and switch to a new branch
git checkout -b feature/your-feature-name

# Or for bug fixes
git checkout -b fix/issue-description
```

### 2. Branch Naming Convention
- `feature/description` - New features
- `fix/description` - Bug fixes  
- `docs/description` - Documentation changes
- `test/description` - Testing improvements
- `refactor/description` - Code refactoring

### 3. Commit Guidelines
```bash
# Make focused, atomic commits
git add specific-files
git commit -m "type: brief description

Optional longer description explaining the change and why it was made.

Fixes #123"
```

### Commit Types
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `test:` - Test additions or modifications
- `refactor:` - Code refactoring
- `chore:` - Maintenance tasks

## Testing

### Required Testing Before Submission

#### 1. Full Deployment Test
```bash
# Test complete deployment flow
./full-deployment.sh dev

# Verify Pentaho is accessible (try direct access first)
curl -I http://<ec2-private-ip>:80/pentaho/Login

# Alternative: SSH tunnel if direct access doesn't work
ssh -L 80:localhost:80 -i ~/.ssh/your-key.pem ubuntu@<ec2-ip>
# Open http://localhost:80/pentaho and log in
```

#### 2. Individual Script Testing
```bash
# Test each script independently
./01-create-pentaho-ec2.sh dev
./02-download-pentaho-files.sh dev
./03-build-pentaho-containers.sh dev
./04-deploy-pentaho.sh dev
```

#### 3. Cleanup Testing
```bash
# Verify teardown works correctly
./teardown-instance.sh dev

# Confirm all resources are cleaned up in AWS console
```

#### 4. Error Handling Testing
```bash
# Test with invalid environment
./01-create-pentaho-ec2.sh nonexistent

# Test with missing files
mv pentaho-downloads/*.zip /tmp/
./02-download-pentaho-files.sh dev
mv /tmp/*.zip pentaho-downloads/
```

### Test Documentation
When submitting changes, include:
- Test scenarios executed
- Expected vs actual results
- Screenshots for UI-related changes
- Performance impact notes

## Submitting Changes

### 1. Update Documentation
- Update README.md if functionality changes
- Add or update inline comments for complex logic
- Update configuration examples if needed

### 2. Create Pull Request
```bash
# Push your branch
git push origin feature/your-feature-name

# Create pull request on GitHub with:
# - Clear title and description
# - Reference to related issues
# - Test results summary
```

### 3. Pull Request Template
```markdown
## Description
Brief description of changes made.

## Type of Change
- [ ] Bug fix
- [ ] New feature  
- [ ] Documentation update
- [ ] Refactoring

## Testing
- [ ] Full deployment test passed
- [ ] Individual script tests passed
- [ ] Error handling tested
- [ ] Cleanup/teardown tested

## Screenshots (if applicable)
[Add screenshots for UI changes]

## Related Issues
Fixes #123
```

### 4. Review Process
- Automated checks must pass
- At least one maintainer review required
- Address review feedback promptly
- Maintain clean git history (squash if needed)

## Coding Standards

### Shell Scripting Standards

#### 1. Script Structure
```bash
#!/bin/bash

# script-name.sh  
# Brief description of what the script does

set -e  # Exit on error

# Configuration section
VARIABLE_NAME="default-value"
ENVIRONMENT=${1:-"dev"}

# Functions
function_name() {
    local local_var="$1"
    echo "Function output"
}

# Main execution
main() {
    echo "Starting script execution..."
    # Script logic here
}

# Call main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

#### 2. Naming Conventions
- **Variables:** `UPPER_CASE` for constants, `lower_case` for local variables
- **Functions:** `snake_case` function names
- **Files:** `kebab-case.sh` for script files

#### 3. Error Handling
```bash
# Always use error handling
set -e

# Check prerequisites
if [ ! -f "required-file.txt" ]; then
    echo "❌ Error: required-file.txt not found"
    exit 1
fi

# Use meaningful error messages
if ! command_that_might_fail; then
    echo "❌ Error: Command failed - check logs for details"
    exit 1
fi
```

#### 4. Logging and Output
```bash
# Use consistent emoji and formatting
echo "🚀 Starting deployment process..."
echo "✅ Step completed successfully"
echo "❌ Error occurred during step"
echo "⚠️  Warning: non-critical issue detected"
echo "📝 Information message"
```

#### 5. Documentation Standards
```bash
# Function documentation
# Purpose: Brief description of what function does
# Parameters: $1 - description of first parameter
# Returns: Description of return value/output
# Example: function_name "parameter_value"
function_name() {
    local param1="$1"
    # Function implementation
}
```

### AWS Resource Standards

#### 1. Resource Naming
- Include environment in resource names: `pentaho-dev-sg`, `pentaho-test-instance`
- Use consistent prefixes across all resources
- Include purpose/component: `pentaho-dev-security-group`

#### 2. Tagging
```bash
# Always tag AWS resources
aws ec2 create-tags --resources ${INSTANCE_ID} --tags \
    Key=Name,Value="${INSTANCE_NAME}" \
    Key=Environment,Value="${ENVIRONMENT}" \
    Key=Project,Value="pentaho-docker-deployment" \
    Key=Owner,Value="${USER}" \
    Key=Purpose,Value="pentaho-server"
```

#### 3. Cleanup Responsibility
- Every resource creation must have corresponding cleanup
- Include cleanup instructions in documentation
- Test teardown scenarios thoroughly

### Git Standards

#### 1. Commit Message Format
```
type(scope): brief description

Longer explanation of the change, including:
- Why the change was needed
- How it addresses the issue
- Any side effects or considerations

Closes #123
```

#### 2. Branch Management
- Keep branches focused and short-lived
- Rebase feature branches before merging
- Delete branches after successful merge

## Getting Help

### Resources
- 📖 **Documentation:** Read the README.md thoroughly
- 🐛 **Issues:** Check existing GitHub issues before creating new ones
- 💬 **Discussions:** Use GitHub Discussions for questions and ideas

### Contact Methods
- **GitHub Issues:** For bugs and feature requests
- **GitHub Discussions:** For general questions and brainstorming
- **Pull Request Comments:** For code-specific discussions

### Response Time Expectations
- **Issues:** Initial response within 48 hours
- **Pull Requests:** Initial review within 1 week
- **Urgent Issues:** Tag as "urgent" and expect faster response

## Recognition

Contributors are recognized in several ways:
- Listed in project README contributors section
- GitHub contribution graphs and statistics
- Mentioned in release notes for significant contributions

Thank you for contributing to make Pentaho deployment easier for everyone! 🚀
