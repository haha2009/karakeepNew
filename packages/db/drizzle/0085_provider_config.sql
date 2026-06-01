CREATE TABLE IF NOT EXISTS `providerConfig` (
	`id` text PRIMARY KEY NOT NULL DEFAULT 'default',
	`baseUrl` text,
	`apiKey` text,
	`textModel` text DEFAULT 'deepseek-v4-pro',
	`imageModel` text DEFAULT 'deepseek-v4-pro',
	`outputSchema` text DEFAULT 'json',
	`createdAt` integer NOT NULL,
	`updatedAt` integer
);