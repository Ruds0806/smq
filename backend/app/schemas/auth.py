from pydantic import BaseModel


class RegisterRequest(BaseModel):
    phone: str
    full_name: str
    password: str


class LoginRequest(BaseModel):
    phone: str
    password: str


class PatientLoginRequest(BaseModel):
    identifier: str
    password: str


class OtpRequest(BaseModel):
    phone: str


class OtpVerifyRequest(BaseModel):
    phone: str
    code: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
