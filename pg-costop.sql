-- by turbo (github.com/turbo)
-- SPDX: MIT

-- required for Gaussian normal random vectors
CREATE EXTENSION IF NOT EXISTS "tablefunc";

-- vector addition
CREATE OR REPLACE FUNCTION ct_add(a double precision[], b double precision[])
RETURNS double precision[] AS
$$
  SELECT array_agg(result)
  FROM (
    SELECT tuple.val1 + tuple.val2 AS result
    FROM (
      SELECT 
        UNNEST(a) AS val1,
        UNNEST(b) AS val2,
        generate_subscripts(a, 1) AS ix
    ) tuple
    ORDER BY ix
  ) inn;
$$ LANGUAGE SQL IMMUTABLE STRICT;

-- vector substraction
CREATE OR REPLACE FUNCTION ct_sub(a double precision[], b double precision[])
RETURNS double precision[] AS
$$
  SELECT array_agg(result)
  FROM (
    SELECT tuple.val1 - tuple.val2 AS result
    FROM (
      SELECT 
        UNNEST(a) AS val1,
        UNNEST(b) AS val2,
        generate_subscripts(a, 1) AS ix
    ) tuple
    ORDER BY ix
  ) inn;
$$ LANGUAGE SQL IMMUTABLE STRICT;

-- normal random vector
CREATE OR REPLACE FUNCTION ct_random_normal(
  dim INTEGER, 
  mean double precision, 
  std double precision
)
RETURNS double precision[] AS
$$
BEGIN
  RETURN ARRAY(SELECT normal_rand(dim, mean, std))::double precision[];
END
$$ LANGUAGE 'plpgsql' STRICT;

-- vector magnitude
CREATE OR REPLACE FUNCTION ct_norm(vector double precision[])
RETURNS double precision AS
$$
BEGIN
  RETURN (
    SELECT SQRT(SUM(pow)) 
    FROM (
      SELECT POWER(e, 2) AS pow
      FROM unnest(vector) AS e
    ) AS norm
  );
END
$$ LANGUAGE 'plpgsql' STRICT;

-- scale vector by constant
CREATE OR REPLACE FUNCTION ct_scale(vec double precision[], c double precision)
RETURNS double precision[] AS
$$
  SELECT array_agg(result)
  FROM (
    SELECT tuple.val1 * c AS result
    FROM (
      SELECT 
        UNNEST(vec) AS val1,
        generate_subscripts(vec, 1) AS ix
    ) tuple
    ORDER BY ix
  ) inn;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ct_weigh(
  IN positive double precision[][],
  IN negative double precision[][] DEFAULT ARRAY[]::double precision[][],
  IN noise double precision DEFAULT NULL,
  IN pos_scale double precision DEFAULT NULL,
  IN neg_scale double precision DEFAULT NULL,
  OUT vec double precision[],
  OUT norm double precision
) AS 
$$
DECLARE
  v double precision[];
  skip BOOLEAN;
BEGIN
  IF positive IS NULL OR cardinality(positive) < 1 THEN
    RAISE 'ct_weigh requires at least one positive weight vector';
  END IF;

  -- unnest array slice 1 (i.e. get first element of 2d array)
  vec := ARRAY(SELECT unnest(positive[1:1]));

  IF pos_scale IS NOT NULL THEN
    vec := ct_scale(vec, pos_scale);
  END IF;

  -- was that it?
  IF cardinality(positive) = 1 THEN
    norm := ct_norm(vec);
    RETURN;
  END IF;

  skip := true;

  FOREACH v SLICE 1 IN ARRAY positive
  LOOP
    IF skip THEN
      skip := false;
    ELSE
      IF pos_scale IS NOT NULL THEN
        v := ct_scale(v, pos_scale);
      END IF;

      vec := ct_add(vec, v);
    END IF;
  END LOOP;

  IF negative IS NOT NULL AND cardinality(negative) > 0 THEN
    FOREACH v SLICE 1 IN ARRAY negative
    LOOP
      IF neg_scale IS NOT NULL THEN
        v := ct_scale(v, neg_scale);
      END IF;

      vec := ct_sub(vec, v);
    END LOOP;
  END IF;

  IF noise IS NOT NULL THEN
    vec := ct_add(
      vec,
      ARRAY(SELECT normal_rand(
        cardinality(vec),
        0,
        noise * vector_norm(vec)
      ))::double precision[]
    );
  END IF;

  norm := ct_norm(vec);
END
$$ language 'plpgsql';

-- dot product
CREATE OR REPLACE FUNCTION ct_dot(
  a double precision[],
  b double precision[]
) 
RETURNS double precision AS 
$$
BEGIN
  RETURN (
    SELECT sum(mul)
    FROM (
      SELECT v1e * v2e as mul
      FROM unnest(a, b) AS t(v1e, v2e)
    ) AS denominator
  );
END
$$ LANGUAGE 'plpgsql' STRICT;

-- vector cosine similarity (in form acceptable to default ORDER)
-- if magnitude for any vector is NULL, it will be calculated
CREATE OR REPLACE FUNCTION ct_similarity(
  a double precision[],
  b double precision[],
  norm_a double precision DEFAULT NULL,
  norm_b double precision DEFAULT NULL
) 
RETURNS double precision AS 
$$
BEGIN
  IF a IS NULL OR b IS NULL THEN
    RAISE 'All vectors must be non-null, got: (%, %)', a, b;
  END IF;

  RETURN -(
    ct_dot(a, b) 
    / (COALESCE(norm_a, ct_norm(a)) * COALESCE(norm_b, ct_norm(b)))
  );
END
$$ LANGUAGE 'plpgsql';

