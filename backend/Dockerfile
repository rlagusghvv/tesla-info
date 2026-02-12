FROM node:24-alpine

WORKDIR /app

# No external deps; keep it simple.
COPY ./ ./

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=8787

EXPOSE 8787

CMD ["node", "server.mjs"]
