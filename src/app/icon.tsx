import { ImageResponse } from "next/og";

export const size = { width: 512, height: 512 };
export const contentType = "image/png";

export default function Icon() {
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
          letterSpacing: "-6px",
        }}
      >
        A-Hely
      </div>
    ),
    size,
  );
}
