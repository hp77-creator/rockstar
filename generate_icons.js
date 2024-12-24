import puppeteer from 'puppeteer';
import fs from 'fs';
import { promises as fsPromises } from 'fs';
import path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function generateIcons() {
    try {
        const iconsetPath = 'ClipboardManager/ClipboardManager/Assets.xcassets/AppIcon.appiconset';
        await fsPromises.mkdir(iconsetPath, { recursive: true });

        // Launch browser with high DPI
        const browser = await puppeteer.launch({
            headless: 'new',
            args: ['--no-sandbox'],
            defaultViewport: {
                width: 1024,
                height: 1024,
                deviceScaleFactor: 2
            }
        });
        
        const page = await browser.newPage();
        
        // Load the icon page
        const htmlPath = path.join(process.cwd(), 'icon_generator.html');
        const htmlContent = await fsPromises.readFile(htmlPath, 'utf8');
        await page.setContent(htmlContent);
        
        // Wait for any animations to settle
        await sleep(1000);

        // Capture the icon at highest resolution
        const iconElement = await page.$('.icon');
        if (!iconElement) {
            throw new Error('Could not find icon element');
        }

        // Save the base 1024x1024 icon
        await iconElement.screenshot({
            path: path.join(iconsetPath, 'icon_1024.png'),
            omitBackground: true
        });

        await browser.close();

        // Generate all required sizes including 64px for 32@2x
        const sizes = [
            { size: 16, name: 'icon_16.png' },
            { size: 32, name: 'icon_32.png' },
            { size: 64, name: 'icon_64.png' }, // For 32@2x
            { size: 128, name: 'icon_128.png' },
            { size: 256, name: 'icon_256.png' },
            { size: 512, name: 'icon_512.png' }
        ];

        // Generate all sizes
        for (const { size, name } of sizes) {
            await execAsync(
                `sips -z ${size} ${size} "${path.join(iconsetPath, 'icon_1024.png')}" --out "${path.join(iconsetPath, name)}"`
            );
            console.log(`Generated ${name}`);
        }

        // Create 2x versions by copying appropriate sizes
        const copies = [
            { from: 'icon_32.png', to: 'icon_16@2x.png' },
            { from: 'icon_64.png', to: 'icon_32@2x.png' },
            { from: 'icon_256.png', to: 'icon_128@2x.png' },
            { from: 'icon_512.png', to: 'icon_256@2x.png' },
            { from: 'icon_1024.png', to: 'icon_512@2x.png' }
        ];

        for (const { from, to } of copies) {
            await execAsync(
                `cp "${path.join(iconsetPath, from)}" "${path.join(iconsetPath, to)}"`
            );
            console.log(`Created ${to} from ${from}`);
        }

        // Clean up intermediate files
        await execAsync(`rm "${path.join(iconsetPath, 'icon_64.png')}"`);

        console.log('Icon generation complete! Generated all required sizes for macOS app icon.');
    } catch (error) {
        console.error('Error generating icons:', error);
        process.exit(1);
    }
}

generateIcons().catch(console.error);
