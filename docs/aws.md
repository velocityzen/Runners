# AWS — CodeBuild-hosted GitHub Actions runners API

Checked 2026-11-15. AWS's managed option is **CodeBuild-hosted GitHub Actions runners**. A CodeBuild *runner project* gets a `WORKFLOW_JOB_QUEUED` webhook, and **each GitHub job becomes one CodeBuild build** that runs an ephemeral runner, then terminates. So "runner status" = CodeBuild build status.

(Self-managed EC2 runners, e.g. the terraform-aws-github-runner module, are covered at the end.)

## How jobs map to builds

```yaml
runs-on: codebuild-<project-name>-${{ github.run_id }}-${{ github.run_attempt }}
# optional overrides on extra label lines:
#   image:arm-3.0   instance-size:small   fleet:<fleet-name>   buildspec-override:true
```

- Project type: **Runner project**, runner provider GitHub, scope repo / org / enterprise.
- Runners register at repo level by default. Org/enterprise via `CODEBUILD_CONFIG_GITHUB_ACTIONS_ORG_REGISTRATION_NAME` / `..._ENTERPRISE_REGISTRATION_NAME`, group via `..._RUNNER_GROUP_ID`.
- Compute: EC2 or Lambda.
- On the GitHub side these show as self-hosted runners with the `codebuild-…` label (see `github-actions.md`).

## API protocol (no SDK)

AWS JSON 1.1 protocol. Every operation is a `POST /`:

```
POST https://codebuild.<region>.amazonaws.com/
Content-Type: application/x-amz-json-1.1
X-Amz-Target: CodeBuild_20161006.<Operation>
X-Amz-Date: 20261115T141500Z
X-Amz-Security-Token: <session token>        # only for temporary (STS/SSO) creds
Authorization: AWS4-HMAC-SHA256 Credential=<AKID>/<yyyymmdd>/<region>/codebuild/aws4_request, SignedHeaders=content-type;host;x-amz-date;x-amz-target, Signature=<hex>
```

Body = JSON request. Timestamps in responses are **epoch seconds as numbers** (fractional), so decode with `.secondsSince1970`.

### SigV4 in Swift (CryptoKit is enough)

1. Canonical request: `POST\n/\n\n` + sorted lowercase headers `name:value\n` + `\n` + signed header list + `\n` + hex(SHA256(body))
2. String to sign: `AWS4-HMAC-SHA256\n<amzDate>\n<date>/<region>/codebuild/aws4_request\n` + hex(SHA256(canonicalRequest))
3. Key: `kDate = HMAC("AWS4"+secret, date)`, `kRegion = HMAC(kDate, region)`, `kService = HMAC(kRegion, "codebuild")`, `kSigning = HMAC(kService, "aws4_request")`
4. Signature = hex(HMAC(kSigning, stringToSign))

`HMAC<SHA256>` and `SHA256` from CryptoKit (or swift-crypto on Linux).

### Credentials

- IAM user access key (simplest for a desktop app), or
- IAM Identity Center / `aws sso login` cache → temporary creds (+ session token), or
- STS `AssumeRole` (also SigV4, `sts.amazonaws.com`, Query protocol).

Minimal IAM policy actions: `codebuild:ListProjects`, `codebuild:BatchGetProjects`, `codebuild:ListBuildsForProject`, `codebuild:BatchGetBuilds`, optionally `codebuild:ListFleets`, `codebuild:BatchGetFleets`.

## Operations

| X-Amz-Target | Request | Response |
|---|---|---|
| `CodeBuild_20161006.ListProjects` | `{ "sortBy": "NAME", "nextToken": … }` | `{ projects: [name], nextToken }` |
| `CodeBuild_20161006.ListBuildsForProject` | `{ "projectName": "…", "sortOrder": "DESCENDING", "nextToken": … }` | `{ ids: [buildId], nextToken }`, ≤ 100 per page |
| `CodeBuild_20161006.ListBuilds` | `{ "sortOrder": "DESCENDING", "nextToken": … }` | all builds in the region, 100/page |
| `CodeBuild_20161006.BatchGetBuilds` | `{ "ids": [ ≤ 100 ] }` | `{ builds: [Build], buildsNotFound: [] }` |
| `CodeBuild_20161006.ListFleets` / `BatchGetFleets` | `{}` / `{ "names": [...] }` | reserved-capacity fleets (if you use `fleet:` labels) |

Status loop: `ListBuildsForProject` (newest first) → `BatchGetBuilds` on the first N ids → treat `buildComplete == false` as live runners.

### Build fields

- `id` (`<project>:<uuid>`), `arn`, `buildNumber`, `projectName`
- `buildStatus`: `SUCCEEDED | FAILED | FAULT | TIMED_OUT | IN_PROGRESS | STOPPED`
- `buildComplete` (bool), `currentPhase`
- `phases[] {phaseType, phaseStatus, startTime, endTime, durationInSeconds}`. Phase types (per the BuildPhase type docs): `SUBMITTED, QUEUED, PROVISIONING, DOWNLOAD_SOURCE, INSTALL, PRE_BUILD, BUILD, POST_BUILD, UPLOAD_ARTIFACTS, FINALIZING, COMPLETED`. The GitHub runner itself runs in `BUILD`.
- `startTime`, `endTime`, `queuedTimeoutInMinutes`, `timeoutInMinutes`
- `environment {type, image, computeType, computeConfiguration{vCpu, memory, disk, instanceType}, fleet{fleetArn}}`
- `resolvedSourceVersion` (commit SHA), `sourceVersion`
- `logs.deepLink` (CloudWatch console URL), `logs.groupName`, `logs.streamName`

Queue time ≈ end of `QUEUED`/`PROVISIONING` phases. The build ↔ GitHub job link is the run id in the label. On the GitHub side, the job's `runner_name`/`labels` include `codebuild-<project>-<run_id>-<attempt>`.

## Self-managed runners on EC2 (alternative setup)

If runners are your own EC2 instances (e.g. `github-aws-runners/terraform-aws-github-runner`):
- runner status: GitHub `GET /orgs/{org}/actions/runners`
- machines: EC2 `DescribeInstances` (Query protocol: `POST https://ec2.<region>.amazonaws.com/` with form body `Action=DescribeInstances&Version=2016-11-15&Filter.1.Name=tag:ghr:environment&Filter.1.Value.1=<env>`, SigV4 service `ec2`, XML response). Tag names depend on the module.

## Sources

- https://docs.aws.amazon.com/codebuild/latest/userguide/action-runner-overview.html
- https://docs.aws.amazon.com/codebuild/latest/userguide/action-runner.html
- https://docs.aws.amazon.com/codebuild/latest/userguide/action-runner-questions.html
- https://docs.aws.amazon.com/codebuild/latest/APIReference/API_ListBuilds.html
- https://docs.aws.amazon.com/codebuild/latest/APIReference/API_ListBuildsForProject.html
- https://docs.aws.amazon.com/codebuild/latest/APIReference/API_BatchGetBuilds.html
- https://docs.aws.amazon.com/codebuild/latest/APIReference/API_Build.html
- https://docs.aws.amazon.com/general/latest/gr/codebuild.html (endpoints)
- https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv-create-signed-request.html (SigV4)
