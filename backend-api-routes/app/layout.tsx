import type { Metadata } from "next";
import { WolfSocialPWARegister } from '@/components/social/WolfSocialPWARegister';
import "./globals.css";

export const metadata: Metadata = {
  title: "WolfGrid Sales",
  description: "The WolfGrid workspace for salespeople.",
  icons: {
    icon: [
      { url: "/wolfsocial-icon-1024.png", type: "image/png", sizes: "1024x1024" },
      { url: "/wolfsocial-icon.svg", type: "image/svg+xml", sizes: "any" },
    ],
    shortcut: "/wolfsocial-icon-1024.png",
    apple: [{ url: "/wolfsocial-icon-1024.png", sizes: "1024x1024", type: "image/png" }],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}<WolfSocialPWARegister /></body>
    </html>
  );
}
