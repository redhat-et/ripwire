# Deployment credentials playbook

These notes describe the credential rotation runbook so `--recall` can surface them. Every value here
is a fake EXAMPLE. When ctxpack recalls this doc body it must redact the live-looking credentials below.

## AWS

Set the deploy access key id `AKIAIOSFODNN7EXAMPLE` in the CI secret store.
The matching value: aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

## GitHub

Personal access token for the release bot: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789

## Anthropic

API key for the summarizer: sk-ant-api03-abcdefGHIJKL1234567890mnopQRST

## Not-a-secret reference (must survive)

The rollback target is git commit da39a3ee5e6b4b0d3255bfef95601890afd80709 — this SHA is prose, not a
credential, and must appear verbatim in recall output.
