from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "SmartQueue RS API"
    environment: str = "development"
    secret_key: str = "change-this-secret-key"
    access_token_expire_minutes: int = 60 * 24
    database_url: str = "sqlite:///./smartqueue.db"
    firebase_server_key: str = ""
    whatsapp_api_url: str = ""
    whatsapp_token: str = ""
    allowed_origins: str = "http://localhost:5176,http://localhost:5173"

    class Config:
        env_file = ".env"


settings = Settings()
