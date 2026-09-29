# PowerToys tools

Tools in PowerToys are standalone apps and scripts that run outside of the PowerToys runner. They help developers and users to debug and test PowerToys features.

The source code of the tools can be found in the [tools folder](/tools). The compiled tools are saved under `{PowerToysInstallPath}\tools`.

## Overview of the tools

Following tools are currently available:

* [BugReportTool](bug-report-tool.md) - A tool to collect logs and system information for bug reports.
* [Build tools](build-tools.md) - A set of scripts that help building PowerToys.
* [Monitor info report](monitor-info-report.md) - A small diagnostic tool which helps identifying WinAPI bugs related to the physical monitor detection.
* [project template](/tools/project_template/README.md) - A Visual Studio project template for a new PowerToys project.
* [StylesReportTool](styles-report-tool.md) - A tool to collect information about an open window.
* [Verification scripts](verification-scripts.md) - A set of scripts that help verifying the PowerToys installation.

## Verification infrastructure design discussions

* [Multi-agent PowerToys verification brainstorm](multi-agent-verification.md) - Historical discussion material, not an approved architecture.
* [Phase-one verification design draft](multi-agent-verification-design.md) - Color Picker checklist/profile refinement, agent contracts, CLI orchestration, and human review boundaries.
* [Phase-one execution plan](multi-agent-verification-execution-plan.md) - Milestones, acceptance evidence, and a clean-main baseline strategy that reuses the current verification improvements.
