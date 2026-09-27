(ns sample.core)

(def answer 42)
(defonce cached 1)
(defn square [x] (* x x))
(defn- secret [x] (square x))
(defmacro unless [pred & body] `(if (not ~pred) ~@body))
(defmulti area :shape)
(defmethod area :circle [{:keys [radius]}] (square radius))
(defmethod route [:get :admin] [request] request)
(#_(ignored) defn #_(ignored-name) spaced [x] (square x))
(; a comment may separate a list opener from its head
 defn ; or a definition head from its name
 commented [x] (square x))
(defn gap-call [x] (#_(ignored-call) square x))
(defn comment-call [x] (; a comment may precede a call head
                        square x))
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
