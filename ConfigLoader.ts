import { consolex } from "../Consolex";
import { UserSettings } from "../game/UserSettings";
import { GameConfig } from "../Schemas";
import { Config, GameEnv, ServerConfig } from "./Config";
import { DefaultConfig } from "./DefaultConfig";
import { DevConfig, DevServerConfig } from "./DevConfig";
import { preprodConfig } from "./PreprodConfig";
import { prodConfig } from "./ProdConfig";

export let cachedSC: ServerConfig = null;

export async function getConfig(
  gameConfig: GameConfig,
  userSettings: UserSettings | null = null,
): Promise<Config> {
  const sc = await getServerConfigFromClient();
  switch (sc.env()) {
    case GameEnv.Dev:
      return new DevConfig(sc, gameConfig, userSettings);
    case GameEnv.Preprod:
    case GameEnv.Prod:
      consolex.log("using prod config");
      return new DefaultConfig(sc, gameConfig, userSettings);
    default:
      throw Error(`unsupported server configuration: ${process.env.GAME_ENV}`);
  }
}
export async function getServerConfigFromClient(): Promise<ServerConfig> {
  if (cachedSC) {
    return cachedSC;
  }
  const response = await fetch("/api/env");

  if (!response.ok) {
    throw new Error(
      `Failed to fetch server config: ${response.status} ${response.statusText}`,
    );
  }
  const config = await response.json();
  // Log the retrieved configuration
  console.log("Server config loaded:", config);

  cachedSC = getServerConfig(config.game_env);
  return cachedSC;
}
export function getServerConfigFromServer(): ServerConfig {
  const gameEnv = process.env.GAME_ENV;
  return getServerConfig(gameEnv);
}
export function getServerConfig(gameEnv: string) {
  switch (gameEnv) {
    case "dev":
      consolex.log("using dev server config");
      return new DevServerConfig();
    case "staging":
      consolex.log("using preprod server config");
      return preprodConfig;
    case "prod":
      consolex.log("using prod server config");
      return prodConfig;
    default:
      throw Error(`unsupported server configuration: ${gameEnv}`);
  }
}
