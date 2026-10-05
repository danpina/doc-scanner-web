// Command-line password reset, for when you can't (or would rather not) use the admin panel.
// Generates a temporary password for the account with this email, or sets the one you give.
// Runs against whatever database .env points at (Turso in production, local SQLite otherwise).
// Usage: node reset-password.js someone@example.com ["a-new-password"]
import { generateTemporaryPassword, hashPassword } from './auth.js';
import { getUserByEmail, updateUser } from './users.js';

const [, , email, chosenPassword] = process.argv;
if (!email) {
  console.error('Usage: node reset-password.js <email> [new-password]');
  process.exit(1);
}
if (chosenPassword && chosenPassword.length < 8) {
  console.error('A password must be at least 8 characters.');
  process.exit(1);
}

const user = await getUserByEmail(email);
if (!user) {
  console.error(`No account with email ${email}.`);
  process.exit(1);
}

const password = chosenPassword || generateTemporaryPassword();
await updateUser(user.id, { passwordHash: await hashPassword(password), passwordSet: true });

console.log(`Password reset for ${user.email}`);
if (!chosenPassword) console.log(`Temporary password: ${password}`);
if (user.appleSub) {
  console.log('Note: this account is linked to Apple; the password lets them log in by email as well.');
}
process.exit(0);
