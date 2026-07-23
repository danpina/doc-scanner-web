// One-off CLI to create a login account (there's no public signup form by design).
// After the first account exists, use the Admin panel in the app instead — this
// script remains mainly for bootstrapping that very first account.
// Usage: node create-user.js you@example.com "your-password" [--admin]
import { hashPassword } from './auth.js';
import { createUser, getUserByEmail, getAllUsers } from './users.js';

const [, , email, password, flag] = process.argv;
if (!email || !password) {
  console.error('Usage: node create-user.js <email> <password> [--admin]');
  process.exit(1);
}

const existing = await getUserByEmail(email);
if (existing) {
  console.error(`A user with email ${email} already exists.`);
  process.exit(1);
}

const isFirstUser = (await getAllUsers()).length === 0;
const isAdmin = isFirstUser || flag === '--admin';

const user = await createUser({ email, passwordHash: await hashPassword(password), isAdmin });
console.log(`Created user ${user.email} (id: ${user.id}, admin: ${isAdmin})`);
process.exit(0);
