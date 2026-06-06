CREATE TABLE `githubProjects` (
	`id` text PRIMARY KEY NOT NULL,
	`userId` text NOT NULL,
	`bookmarkId` text,
	`fullName` text NOT NULL,
	`url` text NOT NULL,
	`name` text NOT NULL,
	`owner` text NOT NULL,
	`description` text,
	`stars` integer,
	`language` text,
	`topics` text,
	`homepage` text,
	`license` text,
	`agentDossier` text,
	`humanSummary` text,
	`tags` text,
	`lastFetchedAt` integer,
	`createdAt` integer NOT NULL,
	`modifiedAt` integer,
	FOREIGN KEY (`userId`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`bookmarkId`) REFERENCES `bookmarks`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `githubProjects_userId_idx` ON `githubProjects` (`userId`);--> statement-breakpoint
CREATE INDEX `githubProjects_fullName_idx` ON `githubProjects` (`fullName`);--> statement-breakpoint
CREATE UNIQUE INDEX `githubProjects_fullName_unique` ON `githubProjects` (`fullName`);--> statement-breakpoint
CREATE TABLE `projectRecommendations` (
	`id` text PRIMARY KEY NOT NULL,
	`projectId` text NOT NULL,
	`bookmarkId` text,
	`recommenderUsername` text,
	`recommenderDisplayName` text,
	`recommenderAvatarUrl` text,
	`originalPostUrl` text,
	`recommendationContext` text,
	`recommendedAt` integer,
	`createdAt` integer NOT NULL,
	FOREIGN KEY (`projectId`) REFERENCES `githubProjects`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`bookmarkId`) REFERENCES `bookmarks`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `projectRecommendations_projectId_idx` ON `projectRecommendations` (`projectId`);--> statement-breakpoint
CREATE INDEX `projectRecommendations_recommenderUsername_idx` ON `projectRecommendations` (`recommenderUsername`);