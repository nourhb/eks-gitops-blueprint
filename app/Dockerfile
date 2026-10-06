# ---- Build stage -------------------------------------------------
FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --omit=dev --ignore-scripts

# ---- Runtime stage ------------------------------------------------
FROM gcr.io/distroless/nodejs20-debian12:nonroot

WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY server.js ./

# Run as the distroless nonroot user (uid 65532)
USER nonroot

EXPOSE 3000
ENV NODE_ENV=production \
    PORT=3000

CMD ["server.js"]
