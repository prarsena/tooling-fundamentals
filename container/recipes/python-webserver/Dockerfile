FROM docker.io/python:alpine

WORKDIR /content

# Add curl for health-check scripts
RUN apk add --no-cache curl

# Copy the static page
COPY index.html index.html

# Expose port 80
EXPOSE 80

# Start the built-in HTTP server
CMD ["python3", "-m", "http.server", "80", "--bind", "0.0.0.0"]
