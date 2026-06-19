import { redirect } from "next/navigation";

export const metadata = {
  title: "GitHub Projects",
};

export default async function ProjectsPage() {
  // GitHub Projects is displayed as a list; redirect to the lists page
  // where the user can select the GitHub list.
  redirect("/dashboard/lists");
}
