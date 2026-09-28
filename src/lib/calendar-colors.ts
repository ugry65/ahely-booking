export const CALENDAR_COLOR_PALETTE = [
  { value: "#F4B6C2", label: "Púderrózsaszín" },
  { value: "#E887A5", label: "Málnarózsaszín" },
  { value: "#F5B895", label: "Barack" },
  { value: "#EE8B7A", label: "Korall" },
  { value: "#C5B3E6", label: "Levendula" },
  { value: "#A991D4", label: "Orgona" },
  { value: "#9273C5", label: "Lila" },
  { value: "#A9D6E5", label: "Babakék" },
  { value: "#83C5E5", label: "Égkék" },
  { value: "#719AC1", label: "Acélkék" },
  { value: "#70C7C2", label: "Türkiz" },
  { value: "#9DD9C5", label: "Menta" },
  { value: "#A8C5A0", label: "Zsályazöld" },
  { value: "#A8D080", label: "Almazöld" },
  { value: "#C1D99B", label: "Pisztácia" },
  { value: "#F2D98D", label: "Vaníliasárga" },
  { value: "#E9BE67", label: "Mézsárga" },
  { value: "#D9BE9C", label: "Homok" },
  { value: "#C9876B", label: "Terrakotta" },
  { value: "#9AAFC1", label: "Szürkéskék" },
] as const;

export const CALENDAR_COLOR_VALUES = CALENDAR_COLOR_PALETTE.map((color) => color.value);
