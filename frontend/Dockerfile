# Start from an official image with Node 18 installed
# (the frontend's build tooling needs a newer Node version than the app itself runs on)
FROM node:16

# Create and switch into a working folder inside the container
WORKDIR /app

# Copy just the dependency files first, so Docker can cache this step
COPY package*.json ./

# Install all dependencies (using install here instead of ci, matching the
# original project setup for the build tooling)
RUN npm install

# Copy the rest of the frontend source code into the container
COPY . .

# Compile the React app into optimized static files (HTML/CSS/JS)
# This creates a "build" folder with the production-ready app
RUN npm run build

# Install a lightweight static file server globally inside the container
# (React apps don't run like the backend — once built, they're just files
# that need to be served, not a live Node process)
RUN npm install -g serve

# Document that this container will listen on port 3000
EXPOSE 3000

# Start the static file server, pointing it at the "build" folder (-s means
# treat it as a single-page app, so browser refreshes on any route still work)
CMD ["serve", "-s", "build"]