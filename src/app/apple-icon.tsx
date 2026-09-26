import { ImageResponse } from "next/og";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#235c43",
          color: "#ffffff",
          fontSize: 46,
          fontWeight: 800,
          letterSpacing: "-2px",
        }}
      >
        A-Hely
      </div>
    ),
    size,
  );
}
