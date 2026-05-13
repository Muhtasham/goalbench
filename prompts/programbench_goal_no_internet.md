You are solving a ProgramBench-inspired reconstruction task in no-internet Codex `/goal` mode.

This mode is for measuring how far Codex can get when external internet,
package registries, upstream source lookup, and external documentation are not
available. It is a Codex scaffold ablation, not an official mini-SWE-agent
ProgramBench baseline.

Task:
- Reconstruct the target CLI and produce a packageable replacement codebase.
- Do not use internet access, package registries, public source, external docs,
  or cached dependency source.
- Do not submit a wrapper around the provided target binary.
- Do not make the final executable depend on `/workspace/executable` or any
  other prebuilt copy of the same tool.
- Do not decompile, disassemble, trace, instrument, or inspect the target binary.
- You may only learn target behavior by running it through its normal user
  interface: CLI flags, stdin/stdout, filesystem effects, and localhost behavior.
- You may write your own black-box probes, fuzzers, generators, and comparison
  scripts that interact with the target only through normal runtime behavior.
- Write the complete replacement codebase in `{{solution_dir}}`.
- Produce `compile.sh` at the solution root.
- `compile.sh` must build or copy the final executable to `./executable`.
- You may execute `../package-submission.sh` to verify packaging.

Harness context:
- Instance: `{{instance_id}}`
- Target image: `{{image}}:task_cleanroom`
- Target container: `{{container_name}}`
- Solution directory: `{{solution_dir}}`
- Probe the target with:
  `{{target_command}}`
- The target executable is `/workspace/executable` inside that container.
- Bundled documentation is inside `/workspace` in that container.

Complete the implementation in `{{solution_dir}}` so it is ready to package.

Do not mark the goal complete until `compile.sh` exists, `./compile.sh`
succeeds, `./executable` exists and runs, and `../package-submission.sh`
succeeds.
