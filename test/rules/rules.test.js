import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, updateDoc, Timestamp } from 'firebase/firestore';
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'todo-ba12a',
    firestore: { rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const now = Timestamp.now();
const task = (over = {}) => ({
  name: 'Buy milk', startDate: null, startTime: null, endDate: null, endTime: null,
  people: [], notes: '', reminder: false, done: false, doneAt: null, createdAt: now, updatedAt: now, ...over,
});
const alice = () => env.authenticatedContext('alice').firestore();
const ref = (db, uid = 'alice', id = 't1') => doc(db, `users/${uid}/tasks/${id}`);

test('owner can create, read, update and delete', async () => {
  const db = alice();
  await assertSucceeds(setDoc(ref(db), task()));
  await assertSucceeds(getDoc(ref(db)));
  await assertSucceeds(updateDoc(ref(db), { name: 'Buy oat milk' }));
  await assertSucceeds(deleteDoc(ref(db)));
});

test("another user cannot read, write or delete someone else's task", async () => {
  await env.withSecurityRulesDisabled((c) => setDoc(ref(c.firestore()), task()));
  const bob = env.authenticatedContext('bob').firestore();
  await assertFails(getDoc(ref(bob)));
  await assertFails(setDoc(ref(bob), task()));
  await assertFails(updateDoc(ref(bob), { name: 'x' }));
  await assertFails(deleteDoc(ref(bob)));
});

test('unauthenticated access is denied', async () => {
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(ref(anon)));
  await assertFails(setDoc(ref(anon), task()));
});

test('a fully populated valid task is accepted', async () => {
  await assertSucceeds(setDoc(ref(alice()), task({
    startDate: '2026-10-15', startTime: '10:00', endDate: '2026-10-15', endTime: '11:00',
    people: ['Ann', 'Bo'], notes: 'n', reminder: true, done: true, doneAt: now,
  })));
});

test('name must be a non-empty string of at most 200 characters', async () => {
  const db = alice();
  await assertSucceeds(setDoc(ref(db), task({ name: 'a'.repeat(200) })));
  await assertFails(setDoc(ref(db), task({ name: 'a'.repeat(201) })));
  await assertFails(setDoc(ref(db), task({ name: '' })));
  await assertFails(setDoc(ref(db), task({ name: '   ' })));
  await assertFails(setDoc(ref(db), task({ name: 42 })));
});

test('people must be a list', async () => {
  await assertFails(setDoc(ref(alice()), task({ people: 'Ann' })));
  await assertFails(setDoc(ref(alice()), task({ people: { a: 1 } })));
});

test('notes must be a string of at most 5,000 characters', async () => {
  const db = alice();
  await assertSucceeds(setDoc(ref(db), task({ notes: 'a'.repeat(5000) })));
  await assertFails(setDoc(ref(db), task({ notes: 'a'.repeat(5001) })));
  await assertFails(setDoc(ref(db), task({ notes: 5 })));
});

test('reminder and done must be booleans', async () => {
  await assertFails(setDoc(ref(alice()), task({ reminder: 'yes' })));
  await assertFails(setDoc(ref(alice()), task({ done: 1 })));
});

test('date and time formats are enforced', async () => {
  const db = alice();
  await assertFails(setDoc(ref(db), task({ startDate: '15/10/2026' })));
  await assertFails(setDoc(ref(db), task({ startDate: '2026-10-15', startTime: '24:00' })));
  await assertFails(setDoc(ref(db), task({ startDate: '2026-10-15', startTime: '9:00' })));
  await assertFails(setDoc(ref(db), task({ startDate: '2026-10-15', endDate: 'tomorrow' })));
  await assertFails(setDoc(ref(db), task({ startDate: '2026-10-15', endTime: '10:60' })));
});

test('time, end and reminder require a start date', async () => {
  const db = alice();
  await assertFails(setDoc(ref(db), task({ startTime: '10:00' })));
  await assertFails(setDoc(ref(db), task({ endDate: '2026-10-15' })));
  await assertFails(setDoc(ref(db), task({ endTime: '10:00' })));
  await assertFails(setDoc(ref(db), task({ reminder: true })));
});

test('unknown fields and missing required fields are rejected', async () => {
  const db = alice();
  await assertFails(setDoc(ref(db), task({ admin: true })));
  const { notes, ...noNotes } = task();
  await assertFails(setDoc(ref(db), noNotes));
});

test('timestamps must be timestamps', async () => {
  await assertFails(setDoc(ref(alice()), task({ createdAt: '2026-10-15' })));
  await assertFails(setDoc(ref(alice()), task({ doneAt: 'yesterday' })));
});

test('an update that breaks the shape is rejected', async () => {
  const db = alice();
  await setDoc(ref(db), task());
  await assertFails(updateDoc(ref(db), { name: 'a'.repeat(201) }));
});
