// One-off CLI to create a login account (there's no public signup form by design).
// Usage: node create-user.js you@example.com "your-password"
import { hashPassword } from './auth.js';
import { createUser, getUserByEmail } from './users.js';

const [, , email, password] = process.argv;
if (!email || !password) {
  console.error('Usage: node create-user.js <email> <password>');
  process.exit(1);
}

const existing = await getUserByEmail(email);
if (existing) {
  console.error(`A user with email ${email} already exists.`);
  process.exit(1);
}

const user = await createUser({ email, passwordHash: await hashPassword(password), isAdmin: true });
console.log(`Created user ${user.email} (id: ${user.id})`);
process.exit(0);
