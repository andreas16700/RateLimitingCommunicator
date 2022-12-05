# 1
FROM swift:5.7-focal

# 2
WORKDIR /app
# 3
COPY . ./
# 4
CMD ["swift", "test"]

