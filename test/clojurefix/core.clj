(ns sample.core)

(def answer 42)
(defonce cached 1)
(defn square [x] (* x x))
(defn- secret [x] (square x))
(defmacro unless [pred & body] `(if (not ~pred) ~@body))
(defmulti area :shape)
(defmethod area :circle [{:keys [radius]}] (square radius))
(defprotocol Greeter (greet [this]))
(defrecord Person [name] Greeter (greet [_] (str "Hi " name)))
(deftype Counter [value])

(def quoted '(defn phantom [] (missing-call)))
(defn quoted-holder [] '(square 1))
`(defn phantom2 [] (other-missing))
#_(defn discarded [] (never-called))

(defn interop []
  (java.lang.String/.toUpperCase "x")
  (Math/abs -1)
  String/1)

(defn run [x] (secret x))
