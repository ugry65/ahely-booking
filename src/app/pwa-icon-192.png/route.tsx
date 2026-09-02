import { ImageResponse } from "next/og";

export const runtime = "edge";

export function GET() {
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
          fontSize: 50,
          fontWeight: 800,
          letterSpacing: "-2px",
          borderRadius: 34,
        }}
      >
        A-Hely
      </div>
    ),
    { width: 192, height: 192 },
  );
}
