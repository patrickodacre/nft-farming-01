import { task, usePlugin } from "@nomiclabs/buidler/config";
import { BuidlerConfig } from "@nomiclabs/buidler/config";

const config: BuidlerConfig = {
    // Your type-safe config goes here
    paths: {
        sources: "./contracts",
        artifacts: "./artifacts",
    },
    solc: {
        version: "0.6.2",
        optimizer: {
            enabled: true,
            runs: 200
        }
    },
};

usePlugin("@nomiclabs/buidler-truffle5");

export default config
