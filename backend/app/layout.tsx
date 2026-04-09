import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "StatShot API",
  description: "Sports alert backend — real-time notifications for player stats and game events",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
