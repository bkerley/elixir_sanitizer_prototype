FROM hexpm/elixir:1.17.2-erlang-27.0.1-debian-bookworm-20240812

RUN addgroup --system app && \
  adduser --system --ingroup app app && \
  mkdir -p /app /mix/deps /mix/home /mix/archives /mix/hex && \
  chown -R app:app /app /mix

USER app:app

WORKDIR /app
ENV MIX_DEPS_PATH=/mix/deps MIX_HOME=/mix/home MIX_ARCHIVES=/mix/archives \
  HEX_HOME=/mix/hex

COPY --chown=app:app mix.exs mix.lock /app
RUN mix do deps.get, deps.compile

COPY --chown=app:app . /app

CMD ["mix", "test"]
