I accidentally deleted this readme so i had to remake it all 😭

# welcome to remote model access
these apps allow you to chat with a llm running on a separate machine which is either on the same internet on your iPhone, Apple watch(coming soon), or Apple TV (coming soon)  or on the same tailscale network (Tailnet), from anywhere.
# how to set up tailscale to let you use your server endpoint on any machine on your tailnet
## assuming both the llm server is successfully hosting and the app is running on your device:
read this for more information: https://tailscale.com/kb/1223/funnel

📡 Go to the settings tab.

📡 Look at your server url that you're hosting from your device and copy the numbers after the ":" at the end, which is your port number.

📡 Open your terminal, and enter ```tailscale funnel [Port Number]``` or for it to always be on in the background, ```tailscale funnel --bg [Port Number]``` EXAMPLE: ```tailscale funnel 1234``` or ```tailscale funnel --bg 1234``` respectively, if your port was "1234".

📡 The terminal should display your tailscale funnel url for this now. Add "/v1/chat/completions" to that url and this will act as your tailscale server endpoint for the app.

📡 You can use the same api key in the app even if it's through tailscale, BUT YOU DONT NEED IT as you are self-hosting.

📡 Put the default identifier as the model request name, for example, "gemma-3-4b-it-qat"

📡 It should work now!
# how to turn off tailscale funneling (If you want)

📡 Use ```tailscale funnel -off [Port Number]```, doesn't matter if it was running in background mode or not, both will turn off with this command.

# privacy
No data is collected. Everything is on device except tailscale and your llm. :)

# coming soon (eventually) 
👀 Sideloading Repo (probably not)

👀 Support for multiple models at a time, but one per chat still (might be complicated as i only have one computer to host llms but we will see)

👀 Apple TV App (maybe this summer)

👀 Central website to also interact with your model. Similar to the apps. (maybe this summer)

~~👀 Image sending support for compatible models~~ not available through the lmstudio api.
