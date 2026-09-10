# Start from an official image that already has Node 16 installed
# (matches the Node version this project needs to run correctly)
FROM node:16

# Create a folder called /app inside the container and switch into it
# All following commands run relative to this folder
WORKDIR /app

# Copy just package.json and package-lock.json first (not the rest of the code yet)
# Docker caches this step, so if only your code changes later (not dependencies),
# rebuilds skip re-installing packages and go much faster
COPY package*.json ./

# Install dependencies inside the container, using the exact locked versions
RUN npm ci

# Now copy the rest of the backend source code into the container
COPY . .

# Document that this container listens on port 8080
# (this is informational only — it doesn't actually publish the port;
# that happens later with the -p flag on `docker run`)
EXPOSE 8080

# The command that runs when the container starts
CMD ["npm", "start"]