// tools/optimize-images.js
// Optimize ICO icons to WebP using sharp
// Usage: node tools/optimize-images.js

const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const publicDir = path.resolve(__dirname, '../public');
const optimizedDir = path.join(publicDir, 'optimized');
if (!fs.existsSync(optimizedDir)) {
	fs.mkdirSync(optimizedDir);
}

// Find all .ico files in public (non-recursive)
const icons = fs.readdirSync(publicDir).filter((f) => f.toLowerCase().endsWith('.ico'));

if (icons.length === 0) {
	console.log('No .ico files found in public/.');
	process.exit(0);
}

icons.forEach(async (icon) => {
	const inputPath = path.join(publicDir, icon);
	const outputPath = path.join(optimizedDir, icon.replace(/\.ico$/, '.webp'));
	if (!fs.existsSync(inputPath)) {
		console.warn(`File not found: ${inputPath}`);
		return;
	}
	try {
		// Read all icon pages, pick the largest for best quality
		const image = sharp(inputPath, { pages: -1 });
		const metadata = await image.metadata();
		let largestPage = 0;
		let largestArea = 0;
		if (metadata.pages && metadata.pages > 1) {
			// Find the largest icon page
			for (let i = 0; i < metadata.pages; i++) {
				const pageMeta = await sharp(inputPath, { page: i }).metadata();
				const area = (pageMeta.width || 0) * (pageMeta.height || 0);
				if (area > largestArea) {
					largestArea = area;
					largestPage = i;
				}
			}
		}
		// Extract largest page
		const largest = sharp(inputPath, { page: largestPage });
		await largest.webp({ quality: 80 }).toFile(outputPath);
		// Report sizes
		const origSize = fs.statSync(inputPath).size / 1024;
		const optSize = fs.statSync(outputPath).size / 1024;
		const savings = 100 - (optSize / origSize) * 100;
		console.log(`${icon} optimized: ${origSize.toFixed(1)} KB → ${optSize.toFixed(1)} KB (${savings.toFixed(0)}% smaller)`);
	} catch (err) {
		console.error(`Error optimizing ${icon}:`, err.message);
	}
});

console.log(`\nOptimization complete! Optimized images saved to: ${optimizedDir}`);
console.log('Update your HTML to reference the new .webp files for best performance.');
