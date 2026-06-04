CREATE TABLE `providerConfig` (
	`id` text PRIMARY KEY NOT NULL,
	`baseUrl` text,
	`apiKey` text,
	`textModel` text,
	`imageModel` text,
	`outputSchema` text,
	`createdAt` integer NOT NULL,
	`updatedAt` integer
);
--> statement-breakpoint
ALTER TABLE `bookmarks` ADD `classificationStatus` text DEFAULT 'pending';