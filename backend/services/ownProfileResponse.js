// backend/services/ownProfileResponse.js
// The signed-in person's own profile as the app's settings screens expect
// it back after a save (`{ success, user }`). One shape for every "save my
// settings" route: PUT /users/me and PUT /users/notification-preferences.
// The preferences route used to answer without `user`, and the app showed
// "Oops, something went wrong" after every successful save (2026-11-01).

/** `user` is a serialized users doc ({ id, ...data }). */
function ownProfileJson(user) {
  return {
    _id: user.id,
    email: user.email,
    displayName: user.displayName,
    firstName: user.firstName,
    lastName: user.lastName,
    phoneNumber: user.phoneNumber,
    profilePicture: user.profilePicture,
    bio: user.bio,
    location: user.location,
    zipcode: user.zipcode || null,
    followersCount: user.followersCount || 0,
    followingCount: user.followingCount || 0,
    preferences: user.preferences || null,
    notificationPreferences: user.notificationPreferences || null,
    createdAt: user.createdAt
  };
}

module.exports = { ownProfileJson };
