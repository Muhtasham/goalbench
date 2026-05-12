# ProgramBench Goal Runner

Small harness for running Codex GPT-5.5 `/goal` against ProgramBench cleanroom
tasks.

The harness keeps the solving workspace separate from the ProgramBench evaluator
repo. It starts the target binary inside a no-network Docker container, gives
Codex a clean writable solution directory, and produces the `submission.tar.gz`
layout that `programbench eval` expects.

ProgramBench is a free-form reimplementation benchmark. The agent should choose
the language, architecture, source layout, abstractions, and build script from
black-box observations of the executable plus documentation already present in
the cleanroom container. It should not receive method signatures, skeletons,
product requirements, hidden hints, or task-specific harness tuning.

If ProgramBench publishes the exact mini-SWE-agent baseline prompt, use it via
`--prompt-template` and keep only the local runtime substitutions needed for the
container name and solution path. As of the last check, the public
mini-SWE-agent repository only included SWE-bench prompts, which ask for git
patches and are not a valid ProgramBench submission format.

## Requirements

- Linux `amd64` host for real runs.
- Docker.
- Codex CLI with `features.goals = true`.
- `tmux`.
- A separate ProgramBench checkout only for evaluation.

The ProgramBench images are published for `linux/amd64`. Docker Desktop on Apple
Silicon can sometimes emulate them, but serious runs should happen on Linux
`amd64`.

## Isolation Model

The target binary runs in a Docker container with `--network none`, so probes
against the original program cannot reach the internet. The generated prompt
also requires probing through `docker exec -u agent ...`; this matters because
the cleanroom executable is execute-only for the `agent` user, while root can
bypass file permissions.

Codex itself runs on the host because it must reach OpenAI. The generated prompt
forbids internet use, package managers, upstream source lookup, decompilers, the
ProgramBench evaluator repository, and external replacement docs for images with
missing documentation. The launcher does not enable web search. If you need hard
enforcement for host shell commands too, run this harness inside a VM or host
environment with an egress policy that only permits Codex/OpenAI traffic.

The Codex launcher uses YOLO mode:

```bash
codex --enable goals -m gpt-5.5 -c model_reasoning_effort='xhigh' \
  -s danger-full-access -a never --no-alt-screen
```

## Optional Host Egress Guard

For a stronger run on Linux, create a dedicated user for the Codex process and
apply the UID-scoped OpenAI egress guard:

```bash
sudo useradd -m codex-runner
sudo scripts/linux-openai-egress-guard.sh apply codex-runner
sudo scripts/linux-openai-egress-guard.sh status codex-runner
```

By default the guard allows DNS plus HTTPS to the currently resolved IPs for:

```text
api.openai.com auth.openai.com chatgpt.com ab.chatgpt.com persistent.oaistatic.com
```

This is intentionally simple and conservative. It is IP-based because Linux
firewalls do not filter by domain name directly; if OpenAI/CDN IPs change during
a long run, refresh the rules by running `apply` again. To remove the guard:

```bash
sudo scripts/linux-openai-egress-guard.sh delete codex-runner
```

For strict compliance, do not give the Codex user broad Docker socket access.
Raw Docker access is effectively root-equivalent and can bypass network
controls. The generated prompts require `docker exec -u agent ...`, but for a
publishable run you should either supervise that boundary or expose only a
narrow wrapper for target execution.

## Metrics

Use ProgramBench's primary metric when reporting results: fully resolved
instances. Almost-resolved and average pass rate are useful diagnostics, but
they should not be the headline score.

## Quickstart

Prepare a `jq` run:

```bash
python3 programbench_goal_runner.py prepare jqlang__jq.b33a763
```

Prepare with an official prompt template when one is available:

```bash
python3 programbench_goal_runner.py prepare jqlang__jq.b33a763 \
  --prompt-template /path/to/official-programbench-prompt.md
```

Start the no-network target container:

```bash
~/pb-goal-runs/gpt55-goal-jq/jqlang__jq.b33a763/start-target.sh
```

Check the compliance-critical container properties:

```bash
~/pb-goal-runs/gpt55-goal-jq/jqlang__jq.b33a763/check-compliance.sh
```

Launch Codex in `tmux` and inject `/goal`:

```bash
~/pb-goal-runs/gpt55-goal-jq/jqlang__jq.b33a763/start-codex-goal.sh
```

Attach to the session:

```bash
tmux attach -t pb-goal-jqlang-jq-b33a763
```

Package the submission:

```bash
~/pb-goal-runs/gpt55-goal-jq/jqlang__jq.b33a763/package-submission.sh
```

Evaluate from a ProgramBench checkout:

```bash
~/pb-goal-runs/gpt55-goal-jq/jqlang__jq.b33a763/eval-submission.sh /path/to/ProgramBench
```

## Pilot Order

1. `testorg__calculator.abc1234` to verify packaging and evaluation mechanics.
2. `wfxr__csview.8ac4de0` or `sclevine__yj.8016400` for a realistic small CLI.
3. `jqlang__jq.b33a763` for the serious long run.
4. `ffmpeg__ffmpeg.360a402` only after the harness proves itself on smaller tasks.
