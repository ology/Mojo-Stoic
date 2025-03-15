# Mojo-Stoic
Perl, Mojolicious, ChatGPT Stoic scholar app

To install:

```shell
# have a modern perl, then
cpanm --installdeps .
sqlite app.db < app.sql
```

To run:

```shell
export OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz0987654321
python3 -m venv .
source ./bin/activate
morbo app.pl --verbose --listen http://192.168.100.50:8080
```

