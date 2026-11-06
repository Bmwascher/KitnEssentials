-- _training_lists.lua: spell ids the merge takes out by hand.
--
-- untrainable: no row ships with one of these ids, whichever input holds it. The
-- client tables can keep a spell a hotfix removed, so a name and a level do not
-- prove a trainer teaches it. A talent that points at one stays, because the
-- character knows the talent and no trainer sells it.
return {
    untrainable = {
        19977, 19978, 19979, 25890, 1038, 25895, 1325499, 1238073,
        1240770, 1240771, 1240772, 1240773, 1240774, 399956,
    },
}
