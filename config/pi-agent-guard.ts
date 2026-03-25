import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { realpath } from "fs/promises";
import { isAbsolute, relative, resolve } from "path";

const SAFE_GIT_SUBCOMMANDS = new Set([
  "blame",
  "cat-file",
  "describe",
  "diff",
  "grep",
  "log",
  "ls-files",
  "ls-remote",
  "ls-tree",
  "rev-list",
  "rev-parse",
  "show",
  "show-ref",
  "shortlog",
  "status",
  "symbolic-ref"
]);

function hasShellControlOperators(command: string) {
  return /[;&|><`\n]/.test(command) || command.includes("$(");
}

function repoContainsPath(repoRoot: string, candidatePath: string) {
  const pathFromRepo = relative(repoRoot, candidatePath);
  return pathFromRepo === "" || (!pathFromRepo.startsWith("..") && !isAbsolute(pathFromRepo));
}

async function canonicalPath(path: string) {
  try {
    return await realpath(path);
  } catch {
    return path;
  }
}

function normalizeToolPath(path: string) {
  return path.replace(/^@+/, "");
}

function safeGitCommand(command: string) {
  const trimmed = command.trim();
  if (trimmed === "") return false;
  if (hasShellControlOperators(trimmed)) return false;

  const match = trimmed.match(/^git\s+([a-z0-9-]+)/i);
  return !!match && SAFE_GIT_SUBCOMMANDS.has(match[1].toLowerCase());
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "read") {
      const inputPath = normalizeToolPath(String(event.input.path || "").trim());
      if (inputPath === "") {
        return { block: true, reason: "Read path must not be empty" };
      }

      const repoRoot = await canonicalPath(resolve(ctx.cwd));
      const requestedPath = await canonicalPath(resolve(ctx.cwd, inputPath));
      if (repoContainsPath(repoRoot, requestedPath)) return undefined;

      return {
        block: true,
        reason: `Read access is limited to files inside the checked out repository (${repoRoot})`
      };
    }

    if (event.toolName === "bash") {
      const command = String(event.input.command || "");
      if (safeGitCommand(command)) return undefined;

      return {
        block: true,
        reason: "Bash access is restricted to non-destructive git inspection commands without shell chaining or redirection"
      };
    }

    return {
      block: true,
      reason: "Only the read and bash tools are available to this agent"
    };
  });
}
