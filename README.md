# pg-costop

Vector arithmetic utilities and weighted, variably randomized cosine similarity search in Postgres.

## Example Usage

This library allows you to perform basic arithmetic on vectors, such as: 

```pgsql
SELECT ct_add(
  a := ARRAY[1,2,3],
  b := ARRAY[4,5,6]
);

-- => {5.0,7.0,9.0}
```

However it's main purpose is facilitating advanced cosine proximity / similarity ranking. Say you're building a Spotify competitor, and you want to offer users a frontpage with recommendations based on tracks they have listened to or liked. If a user disliked a track, similar tracks should also rank lower. Finally you want to show a slightly fresh batch of recommendations every time. That's easy with costop!

Lets build on this example. Each track in our platform's database is represented by a vector generated previously by our magic AI. The vector represents the "feel" or identity of the track, and tracks with a smaller cosine distance between them have a similar feel. We want to optimize the recommendation query, and so next to our vector (which has a cardinality of 100), we also pre-calculate and store it's magnitude. While costop can calculate the magnitude if it is not supplied, that's going to be around 3x slower.

So if we take a look at some sample data:

```pgsql
SELECT vec, magnitude
FROM track_properties
LIMIT 10
```

```json
[
  {
    "vec": [-4.43744993210000000, 22.10746002200000000, 34.09545898440000000, -79.21794128420000000, -40.66732788090000000, 48.03163909910000000, 7.49958276750000000, 15.56112861630000000, -121.58570098880000000, 6.16820621490000000, -63.39702224730000000, 11.55327510830000000, 50.01103210450000000, 49.56256103520000000, 11.54410839080000000, -70.26428222660000000, 13.63951587680000000, 18.20098876950000000, -5.82873439790000000, -78.48036193850000000, -84.23011016850000000, 67.92200469970000000, -37.82934951780000000, 96.60363006590000000, -48.90142440800000000, -7.87157392500000000, 55.80366134640000000, 36.68728256230000000, 26.20443916320000000, -100.69766998290000000, 14.79865741730000000, -53.33053970340000000, -78.81256866460000000, 25.74527168270000000, 69.50791168210000000, -49.72927474980000000, -122.10723876950000000, 84.24948883060000000, 69.43576812740000000, 34.47189712520000000, -30.75948715210000000, -10.19818115230000000, 61.92003631590000000, 53.65451049800000000, -47.13929748540000000, -33.99538040160000000, -38.53485870360000000, -60.34483718870000000, -24.34590911870000000, 42.64239883420000000, 5.59185695650000000, -127.63845825200000000, -41.23598098750000000, 35.88092422490000000, -76.12630462650000000, -25.35723686220000000, -72.36457824710000000, 1.18507289890000000, -53.30847549440000000, -83.74974823000000000, -82.00662994380000000, -65.07209014890000000, -118.70180511470000000, 57.94058990480000000, -33.31725311280000000, -32.33360672000000000, -81.61341857910000000, -8.05749607090000000, 29.19243812560000000, 20.65240287780000000, 8.01358032230000000, 2.73667764660000000, 33.00947570800000000, 36.34382629390000000, -9.59816360470000000, -11.56176090240000000, -27.19181442260000000, 41.67628097530000000, 98.88591766360000000, -42.40296936040000000, -55.85681152340000000, 101.21887969970000000, -17.46896934510000000, 40.40370941160000000, 12.23396778110000000, -55.25162124630000000, 50.01083374020000000, 8.71825218200000000, 28.61510467530000000, -81.74520111080000000, 51.40452194210000000, -47.99239730830000000, -132.47442626950000000, -64.47586059570000000, 41.36410140990000000, -26.68621063230000000, -68.49066162110000000, -69.74295806880000000, -72.57584381100000000, -42.64236068730000000],
    "magnitude": 567.9233
  },
  {
    "vec": [1.48314607140000000, 2.67624783520000000, 8.49940872190000000, 0.09380218390000000, -4.47907876970000000, -0.84740149970000000, 5.83015537260000000, 3.73414492610000000, -10.62790203090000000, 1.04884028430000000, -0.85947906970000000, 0.37547129390000000, 1.00873827930000000, 4.77964591980000000, -4.74055433270000000, -4.94443845750000000, -2.51182174680000000, 5.61057329180000000, 2.58822035790000000, -5.56535911560000000, -9.46886062620000000, 4.96676254270000000, -6.60264492030000000, 8.21836280820000000, -7.04813480380000000, -2.67112159730000000, 4.36127090450000000, 3.65302515030000000, 4.67065143590000000, -4.96347236630000000, -1.49984049800000000, -3.81294393540000000, -16.41612625120000000, 0.63507586720000000, 1.26081514360000000, -0.31485545640000000, -11.84312725070000000, 5.54491901400000000, 4.61627483370000000, 5.56733274460000000, -3.61712503430000000, -1.34634089470000000, 1.23889744280000000, -4.21752643590000000, 2.92170929910000000, 0.04173455390000000, 1.92271137240000000, 0.38014635440000000, 1.25466668610000000, 8.80738639830000000, -1.94717121120000000, -6.26801300050000000, -0.09252355250000000, 0.34039661290000000, -8.17535972600000000, 0.78276950120000000, -3.13373565670000000, -0.06576443460000000, -5.16936540600000000, -1.61087036130000000, -11.18818759920000000, -1.88064920900000000, -5.08728933330000000, 0.49590194230000000, -2.49765181540000000, -0.55674767490000000, -6.37714290620000000, -5.04904317860000000, 3.39625954630000000, 0.20004054900000000, 6.93111324310000000, -0.68639588360000000, 3.31862616540000000, 0.13029925530000000, -1.57837152480000000, 1.59223818780000000, -0.41523024440000000, -2.61051702500000000, 9.10719490050000000, 2.07206869130000000, -2.54725074770000000, 6.49956274030000000, -2.88127255440000000, 2.87980747220000000, 4.91765213010000000, -4.08196544650000000, 8.35620021820000000, 1.47835493090000000, 0.54625040290000000, -4.01129293440000000, 6.81511831280000000, -0.95397168400000000, -7.37796974180000000, -2.64400100710000000, -1.78433191780000000, -2.62039470670000000, -4.13981533050000000, -2.24478054050000000, -3.70239877700000000, -6.29406976700000000],
    "magnitude": 48.442005
  },
  ...
]
```

we're ready to use costop. All vectors in costop are `double precision[]`. Here's an example of how we could rank tracks:

```pgsql
WITH
  liked AS (
    SELECT track_id, vec, magnitude
    FROM track_properties
    WHERE track_id = 'f08507c4-df2e-11ea-ac56-fff589f5856f'
  ),
  dont_like AS (
    SELECT vec, magnitude
    FROM track_properties
    WHERE track_id = 'ecca9126-df2e-11ea-ac56-f7c1f9429c6f'
  ),
  weighted AS (
    SELECT *
    FROM ct_weigh(
      positive := ARRAY(SELECT vec FROM liked)
     ,negative := ARRAY(SELECT vec FROM dont_like)
     ,neg_scale := 0.1
     ,noise := 0.05
    )
  )
SELECT
  tp.track_id,
  ct_similarity(
    a := (select w.vec from weighted w)
   ,b := tp.vec
   ,norm_a := (select w.norm from weighted w)
   ,norm_b := tp.magnitude
  )
FROM track_properties tp
WHERE track_id NOT IN (SELECT track_id FROM liked)
ORDER BY 2
LIMIT 10;
```

That's a lot! Let's find out how this works. 

First, `liked` queries the vectors from the tracks we'd like to see more of. For this example, there's just one track in there. Next, `dont_like` queries vectors for tracks the user doesn't like. Again, just one as an example.

Without respecting likes *and* dislikes, and without the random component, we could just use the vector from the `liked` track directly in the `ct_similarity` function we'll get to in a moment. But that only really works for a single source vector. If we want to recommend tracks based on say the last 5 tracks a user has liked, we need to use `ct_weigh` to compact that into one vector.

So now we use `ct_weigh` to build a `weighted` vector taking into account user preferences and a bit of chance. `positive` receives a list of vectors used to bias the weighted vector towards, whereas `negative` is a list of vectors to bias against. We also have optional `neg_scale` and `pos_scale` parameters. In the example above, all `positive` vectors are counted as they are, but `negative` vectors are scaled to only have 10% of their original impact.

Finally, we add a bit of chance (5%) using the optional `noise` parameter.

Now, we use the resulting vector as the origin and try to find similar tracks by using `ct_similarity`. As mentioned previously we make use of cached magnitude values. `norm_a` comes from the `ct_weigh` output, and `magnitude` from our tracks table. `ct_similarity` returns a value that when used with the default `ORDER BY` (the `2` here just references the second `SELECT`ed value) will sort by most similar first.

We also exclude all input tracks with `WHERE track_id NOT IN (SELECT track_id FROM liked)`, because the most similar tracks are of course the same tracks we put in.

## API Reference

tbd
