import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "A-Hely foglalás",
    short_name: "A-Hely",
    description: "Az A-Hely saját foglalási és havi elszámolási rendszere",
    start_url: "/foglalasok",
    scope: "/",
    display: "standalone",
    background_color: "#f5f3ee",
    theme_color: "#235c43",
    lang: "hu",
    orientation: "any",
    icons: [
      {
        src: "/pwa-icon-192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/pwa-icon-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
    ],
  };
}
