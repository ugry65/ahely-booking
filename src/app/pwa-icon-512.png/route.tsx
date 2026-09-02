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
          fontSize: 132,
          fontWeight: 800,
          letterSpacing: "-5px",
          borderRadius: 92,
        }}
      >
        A-Hely
      </div>
    ),
    { width: 512, height: 512 },
  );
}
