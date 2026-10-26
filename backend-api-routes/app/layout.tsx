import type { Metadata } from "next";
import { ThemeProvider } from '@/lib/theme-provider';
import { WolfSocialPWARegister } from '@/components/social/WolfSocialPWARegister';
import "./globals.css";

// Restore appearance before paint to avoid a light flash when dark mode is saved.
const themeInitScript = `try{var t=localStorage.getItem('wolfgrid-sales-theme')==='dark'?'dark':'light';document.documentElement.classList.toggle('dark',t==='dark');document.documentElement.style.colorScheme=t}catch{}`;

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
    <html lang="en" suppressHydrationWarning>
      <head><script dangerouslySetInnerHTML={{ __html: themeInitScript }} /></head>
      <body><ThemeProvider>{children}<WolfSocialPWARegister /></ThemeProvider></body>
    </html>
  );
}
