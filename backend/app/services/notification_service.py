"""
Notification service.

Currently logs to stdout. To enable real delivery:
- WhatsApp: set WHATSAPP_API_URL and WHATSAPP_TOKEN in .env
- Firebase FCM: set FIREBASE_SERVER_KEY in .env
"""
import logging

from app.core.config import settings

logger = logging.getLogger("notification")


def send_push_notification(target: str, title: str, message: str) -> dict:
    """Send FCM push notification. Falls back to log if key not configured."""
    if settings.firebase_server_key:
        try:
            import urllib.request, json as _json
            payload = _json.dumps({
                "to": target,
                "notification": {"title": title, "body": message},
            }).encode()
            req = urllib.request.Request(
                "https://fcm.googleapis.com/fcm/send",
                data=payload,
                headers={
                    "Authorization": f"key={settings.firebase_server_key}",
                    "Content-Type": "application/json",
                },
            )
            urllib.request.urlopen(req, timeout=5)
            return {"status": "sent", "target": target}
        except Exception as exc:
            logger.warning("FCM send failed: %s", exc)

    logger.info("[NOTIFY] %s | %s: %s", target, title, message)
    return {"status": "logged", "target": target, "title": title, "message": message}


def send_whatsapp(phone: str, message: str) -> dict:
    """Send WhatsApp message via configured provider (Fonnte/Twilio)."""
    wa_url = getattr(settings, "whatsapp_api_url", "")
    wa_token = getattr(settings, "whatsapp_token", "")

    if wa_url and wa_token:
        try:
            import urllib.request, urllib.parse
            data = urllib.parse.urlencode({"target": phone, "message": message}).encode()
            req = urllib.request.Request(
                wa_url,
                data=data,
                headers={"Authorization": wa_token},
            )
            urllib.request.urlopen(req, timeout=5)
            return {"status": "sent", "phone": phone}
        except Exception as exc:
            logger.warning("WhatsApp send failed: %s", exc)

    logger.info("[WHATSAPP] %s: %s", phone, message)
    return {"status": "logged", "phone": phone, "message": message}
