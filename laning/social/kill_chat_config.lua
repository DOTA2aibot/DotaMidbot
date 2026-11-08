-- T022: сообщение прямо задано Artem. Пауза и боевые приказы не используются.
return {
    enabled = true,
    version = "kill-chat-1",
    message = "??",
    poll_interval_s = 0.25,
    chat_interval_s = 3,
    freshness_gap_s = 2,
    event_ttl_s = 15,
    max_pending = 5,
};
