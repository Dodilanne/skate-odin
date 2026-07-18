# Runs the project in debug mode
dev:
  odin run . -debug

check:
  odin check . -vet -disallow-do

build:
  odin build .
