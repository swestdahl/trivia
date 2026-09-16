import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Trivia",
  description: "A party quiz, live leaderboard, and shared photo album.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="antialiased">{children}</body>
    </html>
  );
}
