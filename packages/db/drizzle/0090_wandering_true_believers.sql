ALTER TABLE `githubProjects` ADD `agentTags` text;--> statement-breakpoint
ALTER TABLE `githubProjects` ADD `valueScore` text DEFAULT 'unscored' NOT NULL;--> statement-breakpoint
ALTER TABLE `githubProjects` ADD `archived` integer DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE `githubProjects` ADD `archiveReason` text;