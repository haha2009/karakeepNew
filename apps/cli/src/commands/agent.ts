import { getGlobalOptions } from "@/lib/globals";
import { printError, printObject } from "@/lib/output";
import { getAPIClient } from "@/lib/trpc";
import { Command } from "@commander-js/extra-typings";
import chalk from "chalk";

export const agentCmd = new Command()
  .name("agent")
  .description("AI agent for GitHub project analysis and recommendations");

agentCmd
  .command("find")
  .description("search tracked GitHub projects")
  .option("--query <text>", "search by name, description or summary")
  .option("--language <lang>", "filter by programming language")
  .option("--tag <tag>", "filter by tag")
  .option("--min-stars <n>", "minimum stars", Number)
  .option("--sort <order>", "sort order: asc|desc", "desc")
  .action(async (opts) => {
    const api = getAPIClient();
    try {
      const result = await api.github.search.query({
        query: opts.query,
        language: opts.language,
        tag: opts.tag,
        minStars: opts.minStars,
        sortOrder: opts.sort as "asc" | "desc" | undefined,
      });

      if (getGlobalOptions().json) {
        printObject(result);
        return;
      }

      if (result.projects.length === 0) {
        console.log(chalk.yellow("No projects found."));
        return;
      }

      console.log(
        chalk.bold(`\nFound ${result.projects.length} project(s):\n`),
      );
      for (const p of result.projects) {
        const stars = p.stars ? chalk.yellow(`${p.stars}★`) : "";
        const lang = p.language ? chalk.cyan(p.language) : "";
        const summary = p.humanSummary ? chalk.dim(` — ${p.humanSummary}`) : "";
        console.log(
          `  ${chalk.green(p.fullName)}  ${stars}  ${lang}${summary}`,
        );
      }
      console.log();
    } catch (error) {
      printError("Failed to search projects")(error as object);
    }
  });

agentCmd
  .command("project")
  .description("get detailed info about a tracked GitHub project")
  .argument("<fullName>", "owner/repo (e.g. facebook/react)")
  .action(async (fullName) => {
    const api = getAPIClient();
    try {
      const result = await api.github.get.query({ fullName });

      if (!result) {
        console.log(chalk.yellow(`Project "${fullName}" not found.`));
        return;
      }

      if (getGlobalOptions().json) {
        printObject(result);
        return;
      }

      console.log(`\n${chalk.bold.green(result.fullName)}`);
      console.log(`  ${chalk.dim(result.url)}`);
      if (result.stars) console.log(`  ${chalk.yellow(`${result.stars}★`)}`);
      if (result.language) console.log(`  ${chalk.cyan(result.language)}`);
      if (result.license) console.log(`  ${chalk.magenta(result.license)}`);
      if (result.description) console.log(`  ${chalk.dim(result.description)}`);
      if (result.humanSummary)
        console.log(`\n  ${chalk.italic(result.humanSummary)}`);
      if (result.topics && result.topics.length > 0) {
        console.log(
          `\n  Topics: ${result.topics.map((t) => chalk.blue(t)).join(", ")}`,
        );
      }
      if (result.tags && result.tags.length > 0) {
        console.log(
          `  Tags: ${result.tags.map((t) => chalk.green(t)).join(", ")}`,
        );
      }
      if (result.agentDossier) {
        console.log(`\n  ${chalk.bold("Agent Dossier:")}`);
        const dossier = result.agentDossier as Record<string, unknown>;
        for (const [key, value] of Object.entries(dossier)) {
          const label = key
            .replace(/([A-Z])/g, " $1")
            .replace(/^./, (s) => s.toUpperCase());
          const val = Array.isArray(value)
            ? value.join(", ")
            : String(value ?? "");
          console.log(`    ${chalk.dim(label)}: ${val}`);
        }
      }
      console.log();
    } catch (error) {
      printError("Failed to get project")(error as object);
    }
  });

agentCmd
  .command("recommend")
  .description("get project recommendations based on what you want to build")
  .argument("<description>", "describe what you want to build")
  .option("--limit <n>", "max recommendations", Number, 5)
  .action(async (description, opts) => {
    const api = getAPIClient();
    try {
      const result = await api.github.recommend.query({
        description,
        limit: opts.limit,
      });

      if (getGlobalOptions().json) {
        printObject(result);
        return;
      }

      if (result.projects.length === 0) {
        console.log(
          chalk.yellow(
            "No matching projects found. Try tracking more GitHub projects first.",
          ),
        );
        return;
      }

      console.log(`\n${chalk.bold("Top recommendations:")}\n`);
      for (let i = 0; i < result.projects.length; i++) {
        const p = result.projects[i];
        const stars = p.stars ? chalk.yellow(`${p.stars}★`) : "";
        const lang = p.language ? chalk.cyan(p.language) : "";
        const summary = p.humanSummary ? chalk.dim(` — ${p.humanSummary}`) : "";
        console.log(
          `  ${i + 1}. ${chalk.green(p.fullName)}  ${stars}  ${lang}${summary}`,
        );
      }
      console.log(`\n  ${chalk.dim(result.matchReason)}`);
      console.log();
    } catch (error) {
      printError("Failed to get recommendations")(error as object);
    }
  });

agentCmd
  .command("profile")
  .description("show your interest profile from tracked GitHub projects")
  .action(async () => {
    const api = getAPIClient();
    try {
      const result = await api.github.profile.query();

      if (getGlobalOptions().json) {
        printObject(result);
        return;
      }

      console.log(`\n${chalk.bold("Your GitHub Project Profile")}\n`);
      console.log(
        `  ${chalk.dim("Total projects:")} ${chalk.bold(result.totalProjects)}`,
      );
      console.log(
        `  ${chalk.dim("Total stars:")} ${chalk.yellow(`${result.totalStars}★`)}`,
      );
      console.log(
        `  ${chalk.dim("Avg stars/project:")} ${chalk.yellow(`${result.avgStars}★`)}`,
      );

      if (result.languages.length > 0) {
        console.log(`\n  ${chalk.bold("Languages:")}`);
        for (const lang of result.languages.slice(0, 10)) {
          const bar = "█".repeat(Math.min(lang.count, 20));
          console.log(
            `    ${chalk.cyan(lang.language.padEnd(15))} ${bar} ${lang.count}`,
          );
        }
      }

      if (result.topTags.length > 0) {
        console.log(`\n  ${chalk.bold("Top Tags:")}`);
        for (const tag of result.topTags.slice(0, 10)) {
          console.log(`    ${chalk.green(tag.tag.padEnd(20))} ${tag.count}`);
        }
      }

      console.log();
    } catch (error) {
      printError("Failed to get profile")(error as object);
    }
  });
