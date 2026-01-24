# Incident Reports

This directory contains documentation of incidents detected and remediated by the Azure SRE Agent in the Proactive Reliability demo.

## Purpose

The incident reports serve as:
- **Audit Trail**: Record of automated remediation actions taken by the SRE Agent
- **Learning Resource**: Examples of the agent's detection and response capabilities
- **Reference Documentation**: Templates for understanding incident patterns

## Incident Format

Each incident is documented with:
- **Detection**: What metrics/alerts triggered the incident
- **Baseline**: Historical performance data used for comparison
- **Current State**: Observed metrics during the incident
- **Action Taken**: Automated remediation steps executed
- **Post-Remediation**: Results after remediation
- **Analysis**: Root cause and recommendations

## Incident Naming Convention

Incidents are named using the format: `YYYY-MM-DD-brief-description.md`

Example: `2026-01-24-high-response-time.md`

## Related Resources

- [Proactive Reliability Demo README](../README.md)
- [DeploymentHealthCheck SubAgent](../SubAgents/DeploymentHealthCheck.yaml)
- [SRE Agent Documentation](https://github.com/microsoft/sre-agent)
