FROM hexpm/elixir:1.17.2-erlang-27.0.1-debian-bookworm-20240812

RUN addgroup --system app && \
  adduser --system --ingroup app app && \
  mkdir /app

WORKDIR /app

COPY --chown=app:app mix.exs mix.lock /app
RUN mix do deps.get, deps.compile

COPY --chown=app:app . /app

CMD ["mix", "test"]
