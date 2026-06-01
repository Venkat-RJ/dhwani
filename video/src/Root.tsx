import { Composition } from "remotion";
import { Explainer } from "./Demo";

export const RemotionRoot = () => {
  return (
    <Composition
      id="Explainer"
      component={Explainer}
      durationInFrames={870}
      fps={30}
      width={1280}
      height={720}
    />
  );
};
