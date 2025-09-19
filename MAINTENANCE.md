# KTD Package Management Maintenance Guide

This document explains how to maintain and update the package management system for Koha Testing Docker (KTD).

## Overview

KTD uses a centralized YAML-based package management system that handles packages across multiple Linux distributions. The system is designed with newer OS versions as the reference, with older versions using overrides when needed.

## Architecture

### Files
- `files/package-config.yaml` - Central package configuration
- `files/install-packages` - Perl script that processes the YAML and installs packages
- All `Dockerfiles` - Use the centralized system via `/usr/local/bin/install-packages`

### Package Sets
- **base** - Core development packages (apache2, build-essential, git, etc.)
- **koha-dev** - Koha-specific development packages (perltidy, libdevel-cover-perl, etc.)
- **nodejs** - Node.js and Yarn
- **utility** - Utility packages (bugz, inotify-tools)
- **cypress** - Cypress testing packages (libgtk, xvfb, etc.)
- **temp** - Temporary packages for development
- **cpan** - CPAN modules (currently empty but infrastructure ready)

## Design Principles

### 1. Newest OS as Reference
The `common` section in the YAML contains packages that work on the **newest supported OS versions**. This ensures we're moving forward with current standards.

**Current reference distributions:**
- Ubuntu 24.04 (noble)
- Debian 12 (bookworm) 
- Debian trixie

### 2. Older OS Overrides
Older distributions use the `distro_specific` section to override packages that have different names or versions.

### 3. Sid Exception
Debian `sid` (unstable) should **never** be used as the reference, even if it's technically newer. It should always have overrides because:
- Packages change frequently
- Package names may be experimental
- It's not a stable reference point

## Adding New Packages

### Step 1: Determine the Package Set
Identify which logical group your package belongs to:
- System/development tools → `base`
- Koha-specific development → `koha-dev`
- Testing frameworks → `cypress`
- Utilities → `utility`
- Temporary/experimental → `temp`
- Perl modules from CPAN → `cpan`

### Step 2: Add to Common Section
Add the package to the appropriate section in `common` using the **newest OS package name**:

```yaml
common:
  base:
    - apache2
    - build-essential
    - your-new-package  # Use newest OS name
```

### Step 3: Check Older Distributions
Test or verify the package name on older distributions. If different, add overrides:

```yaml
distro_specific:
  focal:  # Ubuntu 20.04
    base-overrides:
      your-new-package: old-package-name
  
  bullseye:  # Debian 11
    base-overrides:
      your-new-package: different-old-name
```

### Step 4: Handle Special Cases

#### Package Removal
If a package doesn't exist on certain distributions:
```yaml
distro_specific:
  trixie:
    cypress-overrides:
      libgconf-2-4: null  # Remove this package
```

#### Empty Package Sets
To define an empty package set (no packages to install):
```yaml
common:
  temp: []  # Empty package set
```

#### Additional Packages
If a distribution needs extra packages:
```yaml
distro_specific:
  bookworm:
    base:
      - extra-package-only-needed-here
```

## Common Override Patterns

### Package Name Evolution
```yaml
# Common (newest)
common:
  base:
    - netcat-openbsd
    - python3-gdbm

# Older distributions
distro_specific:
  focal:
    base-overrides:
      netcat-openbsd: netcat
      python3-gdbm: python-gdbm
```

### Architecture Suffixes
```yaml
# Common
common:
  cypress:
    - libgtk2.0-0
    - libasound2

# Ubuntu 24.04 has t64 packages
distro_specific:
  noble:
    cypress-overrides:
      libgtk2.0-0: libgtk2.0-0t64
      libasound2: libasound2t64
```

## Testing Changes

### 1. Local Testing
```bash
# Test package resolution for specific OS
cd files/
echo "focal" | perl -I. -e '
use Modern::Perl;
use YAML::XS;
my $config = YAML::XS::LoadFile("package-config.yaml");
# Test your logic here
'
```

### 2. Docker Build Testing
```bash
# Test specific distribution
docker build -t test-focal dists/focal/

# Check package installation output
docker build --no-cache -t test-focal dists/focal/ 2>&1 | grep "Installing"
```

### 3. Multi-Distribution Testing
Test at least:
- One old Ubuntu (focal)
- One current Ubuntu (jammy/noble)
- One old Debian (bullseye)
- One current Debian (bookworm)

## Troubleshooting

### Package Not Found
1. Check if package name differs between distributions
2. Verify package exists in distribution repositories
3. Check if package moved to different repository (universe, contrib, etc.)

### Override Not Working
1. Verify YAML syntax (no tabs, proper indentation)
2. Check override key name matches pattern: `{set}-overrides`
3. Ensure package name in override exactly matches common section

### Build Failures
1. Check bootstrap dependencies are installed first
2. Verify Koha repository is properly configured
3. Check for circular dependencies

## Best Practices

1. **Always test on multiple distributions** before committing
2. **Use newest OS package names** in common sections
3. **Document why overrides exist** in comments
4. **Keep sid as exception** - never use as reference
5. **Group related changes** in single commits
6. **Update REFRESHED_AT** when making significant changes

## Examples

### Adding a New Development Tool
```yaml
# Add to common section
common:
  koha-dev:
    - existing-packages
    - new-dev-tool

# Test on older distributions, add overrides if needed
distro_specific:
  focal:
    koha-dev-overrides:
      new-dev-tool: old-dev-tool-name  # if different
```

### Adding CPAN Module
```yaml
common:
  cpan:
    - Existing::Module
    - New::Module::Name
```

### Removing Deprecated Package
```yaml
distro_specific:
  old-distro:
    base-overrides:
      deprecated-package: null  # Remove from old distro
```
