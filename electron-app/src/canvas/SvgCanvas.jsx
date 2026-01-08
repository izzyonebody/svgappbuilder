import React from "react";
import { Stage, Layer, Rect } from "react-konva";

export default function SvgCanvas() {
  return (
    <Stage width={900} height={800}>
      <Layer>
        <Rect x={50} y={60} width={300} height={90} fill="#4CAF50" cornerRadius={6} />
      </Layer>
    </Stage>
  );
}
