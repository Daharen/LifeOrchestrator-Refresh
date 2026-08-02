# Deploying the service

This guide explains how to deploy the collective agent service to production.

## Prerequisites

You need an approved change ticket and a healthy staging environment first.

## Deploy steps

Run the deploy script, then watch the health endpoint until it reports ready.
Promote the release only after the smoke checks pass on the canary instance.

## Rollback

If the canary smoke checks fail, roll back to the previous release immediately.
