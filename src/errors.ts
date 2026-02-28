export class AppError extends Error {
  public readonly code: string;
  public readonly statusCode: number;

  public constructor(code: string, message: string, statusCode: number) {
    super(message);
    this.name = "AppError";
    this.code = code;
    this.statusCode = statusCode;
  }
}

export class HumanInterventionRequiredError extends Error {
  public readonly reason: string;
  public readonly artifacts: string[];

  public constructor(reason: string, artifacts: string[] = []) {
    super(reason);
    this.name = "HumanInterventionRequiredError";
    this.reason = reason;
    this.artifacts = artifacts;
  }
}
