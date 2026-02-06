---
title: 'Стратегии кеширования'
date: '2026-01-14T09:34:19+03:00'
description: >-
  Обзор стратегий кеширования
categories:
  - Tutorial
tags:
  - cache
  - architecture
draft: true
mermaid: true
---

## Cache aside
Cначала проверяется кэш, при промахе обращается к базе, сохраняем результат в кэш и возвращает его.

{{< mermaid >}}
sequenceDiagram
    participant Client
    participant App as Application
    participant Cache
    participant DB as Database

    Client->>App: Запрос данных (key)
    App->>Cache: Get(key)
    alt Кэш hit
        Cache-->>App: Данные
        App-->>Client: Ответ
    else Кэш miss
        Cache-->>App: Нет данных
        App->>DB: Запрос из БД
        DB-->>App: Данные
        App->>Cache: Set(key, data)
        App-->>Client: Ответ
    end
{{< /mermaid >}}

### Пример на go
```go
func (s *Service) GetUser(ctx context.Context, ID int64) (*models.User, err) {
  // 1. Сначала проверяем кэш
  user, err := s.cache.GetUser(ctx, ID)
  if err != nil {
    // тут нужно принять решение пойти в базу или вернуть ошибку
    return nil, fmt.Errorf("cache.GetUser: %w", err)
  }

  // 2. Получаем из БД при промахе
  user, err := s.db.GetUser(ctx, ID)
  if err != nil {
    return nil, fmt.Errorf("db.GetUser: %w", err)
  }

  // 3. Кладем в кеш
  // в prod лучше асинхронно с повторными попытками
  if err := s.cache.SetUser(ctx, user); err != nil {
    slog.WarnContext(ctx, "cache.SetUser", "err", err)
  }

  return user, nil
}
```