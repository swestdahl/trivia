import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Sock Hop Trivia Night",
  description: "Rock around the clock with 1950s trivia, birthday memories, a live leaderboard, and party photos.",
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
