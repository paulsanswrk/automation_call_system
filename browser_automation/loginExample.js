import LoginAutomation from './loginAutomation.js';
import dotenv from 'dotenv';

async function main() {
    const loginBot = new LoginAutomation();
    
    try {
        dotenv.config({ override: true });

        const loginUrl = 'https://example.com/login';
        const targetUrl = 'https://discord.com/channels/793098557715906597/1076832098452770876';
        const username = process.env.DISCORD_UN;
        const password = process.env.DISCORD_PWD;

        await loginBot.openLoginPage(loginUrl);
        
        // Browser will stay open until you call close()
        // You can interact with the page manually
        
        // When you're done, call:
        // await loginBot.close();
    } catch (error) {
        console.error('Error:', error);
    }
}

main(); 